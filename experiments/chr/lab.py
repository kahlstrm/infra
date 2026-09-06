#!/usr/bin/env python3
"""Persistent local QEMU/CHR lab with optional experiment scenarios."""

import argparse
from contextlib import contextmanager
import fcntl
import importlib
import os
from pathlib import Path
import re
import secrets
import select
import shutil
import socket
import subprocess
import sys
import time
import zipfile


SOURCE = Path(__file__).resolve().parent
ANSI = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")


def run(*args, **kwargs):
    return subprocess.run(args, check=True, text=True, **kwargs)


def download(url, destination):
    if destination.exists():
        return
    temporary = destination.with_suffix(destination.suffix + ".part")
    run("curl", "-fsSL", "--retry", "2", url, "-o", str(temporary))
    temporary.replace(destination)


class Lab:
    def __init__(self, args):
        self.version = args.version
        self.root = args.state.resolve()
        self.directory = self.root / self.version
        self.directory.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.disk = self.directory / "disk.qcow2"
        self.key = self.directory / "id_ed25519"
        self.ssh_port = args.ssh_port
        port_file = self.directory / "ports"
        if self.running() and port_file.exists():
            self.ssh_port = int(port_file.read_text().split()[0])

    def running(self):
        pidfile = self.directory / "qemu.pid"
        if not pidfile.exists():
            return False
        try:
            pid = int(pidfile.read_text())
            command = Path(f"/proc/{pid}/cmdline").read_bytes()
            return f"file={self.disk},format=qcow2,if=virtio".encode() in command.split(
                b"\0"
            )
        except (ValueError, FileNotFoundError, ProcessLookupError):
            return False

    def ssh_args(self):
        return [
            "ssh",
            "-o",
            "BatchMode=yes",
            "-o",
            "IdentitiesOnly=yes",
            "-o",
            "ConnectTimeout=3",
            "-o",
            "LogLevel=ERROR",
            "-o",
            "StrictHostKeyChecking=accept-new",
            "-o",
            f"UserKnownHostsFile={self.directory / 'known_hosts'}",
            "-i",
            str(self.key),
            "-p",
            str(self.ssh_port),
            "admin@127.0.0.1",
        ]

    def ssh(self, command):
        if not self.running():
            raise RuntimeError("Lab is stopped; run start first")
        result = run(*self.ssh_args(), command, capture_output=True, timeout=30)
        output = result.stdout.replace("\r", "")
        if re.search(
            r"(?im)^(failure:|syntax error|bad command name|expected end of command|no such item)",
            output,
        ):
            raise RuntimeError(output)
        return output

    def prepare(self):
        images = self.root / "images"
        images.mkdir(exist_ok=True)
        archive = images / f"chr-{self.version}.img.zip"
        image = images / f"chr-{self.version}.img"
        download(
            f"https://download.mikrotik.com/routeros/{self.version}/{archive.name}",
            archive,
        )
        if not image.exists():
            with zipfile.ZipFile(archive) as zipped:
                with zipped.open(image.name) as source, image.open("wb") as target:
                    shutil.copyfileobj(source, target)
            image.chmod(0o400)
        if not self.disk.exists():
            run(
                "qemu-img",
                "create",
                "-f",
                "qcow2",
                "-F",
                "raw",
                "-b",
                str(image),
                str(self.disk),
            )
        if not self.key.exists():
            run("ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", str(self.key))

    def bootstrap(self):
        password_file = self.directory / "password"
        if not password_file.exists():
            password_file.write_text(secrets.token_urlsafe(32))
            password_file.chmod(0o600)
        password = password_file.read_text()
        public_key = self.key.with_suffix(".pub").read_text().strip()
        with socket.socket(socket.AF_UNIX) as console:
            console.connect(str(self.directory / "serial.sock"))
            console.sendall(b"\r")
            buffer = ""
            deadline = time.monotonic() + 90
            while time.monotonic() < deadline:
                if not select.select([console], [], [], 0.25)[0]:
                    continue
                data = console.recv(65536)
                if not data:
                    raise RuntimeError("CHR console disconnected during bootstrap")
                buffer += ANSI.sub("", data.decode(errors="replace"))
                response = None
                if "\x1bZ" in buffer:
                    response = "\x1b[?1;2c"
                elif "Login:" in buffer:
                    response = "admin+ct\r"
                elif "Password:" in buffer:
                    response = "\r"
                elif "Do you want to see the software license" in buffer:
                    response = "n\r"
                elif "new password>" in buffer or "repeat new password>" in buffer:
                    response = password + "\r"
                elif re.search(r"\[admin@[^\]]+\] >", buffer):
                    break
                if response is not None:
                    console.sendall(response.encode())
                    buffer = ""
            else:
                raise RuntimeError(
                    "Timed out bootstrapping CHR; inspect the serial console"
                )
            commands = [
                "/system/identity/set name=chr-lab",
                "/ip/service/disable [find name!=ssh]",
                f'/file/add name=lab.pub type=file contents="{public_key}"',
                "/user/ssh-keys/import user=admin public-key-file=lab.pub",
                '/file/remove [find name="lab.pub"]',
            ]
            for command in commands:
                console.sendall((command + "\r").encode())
                buffer = ""
                deadline = time.monotonic() + 10
                while time.monotonic() < deadline:
                    if select.select([console], [], [], 0.25)[0]:
                        buffer += ANSI.sub(
                            "", console.recv(65536).decode(errors="replace")
                        )
                        if re.search(r"\[admin@[^\]]+\] >\s*$", buffer):
                            break
                else:
                    raise RuntimeError(
                        f"Console command timed out: {command.split()[0]}"
                    )
                if re.search(
                    r"(?im)^(failure:|syntax error|bad command name|expected end of command)",
                    buffer,
                ):
                    raise RuntimeError(f"Console command failed: {buffer}")

    def start(self):
        if self.running():
            print(f"CHR {self.version} is already running")
            return
        self.prepare()
        for name in ("serial.sock", "monitor.sock", "qemu.pid"):
            (self.directory / name).unlink(missing_ok=True)
        captures = self.directory / "captures"
        captures.mkdir(exist_ok=True)
        capture = captures / f"{time.time_ns()}.pcap"
        run(
            "qemu-system-x86_64",
            "-name",
            f"chr-{self.version}",
            "-enable-kvm",
            "-cpu",
            "host",
            "-m",
            "512",
            "-smp",
            "2",
            "-drive",
            f"file={self.disk},format=qcow2,if=virtio",
            "-netdev",
            f"user,id=lab,hostfwd=tcp:127.0.0.1:{self.ssh_port}-:22",
            "-device",
            "virtio-net-pci,netdev=lab",
            "-object",
            f"filter-dump,id=capture,netdev=lab,file={capture}",
            "-display",
            "none",
            "-serial",
            f"unix:{self.directory / 'serial.sock'},server=on,wait=off",
            "-monitor",
            f"unix:{self.directory / 'monitor.sock'},server=on,wait=off",
            "-pidfile",
            str(self.directory / "qemu.pid"),
            "-daemonize",
        )
        (self.directory / "ports").write_text(f"{self.ssh_port}\n")
        if not (self.directory / "configured").exists():
            self.bootstrap()
        deadline = time.monotonic() + 60
        while time.monotonic() < deadline:
            try:
                output = self.ssh("/system/resource/print")
                if f"version: {self.version} " not in output:
                    raise RuntimeError(f"Unexpected RouterOS version:\n{output}")
                (self.directory / "configured").touch()
                print(f"CHR {self.version} ready: SSH 127.0.0.1:{self.ssh_port}")
                print(f"State: {self.directory}\nCapture: {capture}")
                return
            except subprocess.CalledProcessError:
                time.sleep(1)
        raise RuntimeError(
            "CHR started but SSH did not become ready; VM left running for diagnosis"
        )

    def monitor(self, command):
        if not self.running():
            raise RuntimeError("Lab is stopped; run start first")
        with socket.socket(socket.AF_UNIX) as monitor:
            monitor.settimeout(10)
            monitor.connect(str(self.directory / "monitor.sock"))

            def read_prompt():
                output = b""
                while not output.endswith(b"(qemu) "):
                    chunk = monitor.recv(65536)
                    if not chunk:
                        raise RuntimeError("QEMU monitor disconnected")
                    output += chunk
                return ANSI.sub("", output.decode(errors="replace"))

            read_prompt()
            monitor.sendall((command + "\n").encode())
            output = read_prompt()
        if re.search(
            r"(?im)(error:|could not|invalid |unknown command|not found)", output
        ):
            raise RuntimeError(f"QEMU command failed: {output}")
        return output

    @contextmanager
    def forward(self, protocol, host_port, guest_port):
        if protocol not in ("tcp", "udp"):
            raise ValueError("forward protocol must be tcp or udp")
        if not 1024 <= host_port <= 65535 or not 1 <= guest_port <= 65535:
            raise ValueError("invalid forwarding ports")
        if protocol == "tcp" and host_port == self.ssh_port:
            raise ValueError("forward cannot use the SSH management port")
        self.monitor(f"hostfwd_add lab {protocol}:127.0.0.1:{host_port}-:{guest_port}")
        try:
            yield host_port
        finally:
            self.monitor(f"hostfwd_remove lab {protocol}:127.0.0.1:{host_port}")

    def stop(self):
        if not self.running():
            print(f"CHR {self.version} is stopped")
            return
        with socket.socket(socket.AF_UNIX) as monitor:
            monitor.connect(str(self.directory / "monitor.sock"))
            monitor.sendall(b"system_powerdown\n")
        deadline = time.monotonic() + 30
        while self.running() and time.monotonic() < deadline:
            time.sleep(0.25)
        if self.running():
            raise RuntimeError("CHR did not shut down after ACPI request; left running")
        print(f"CHR {self.version} stopped; disk and captures retained")

    def fresh(self):
        self.stop()
        archive = self.directory / "archives" / str(time.time_ns())
        archive.mkdir(parents=True)
        for name in ("disk.qcow2", "known_hosts", "password", "configured", "ports"):
            source = self.directory / name
            if source.exists():
                source.replace(archive / name)
        print(f"Previous lab disk and configuration archived in {archive}")
        self.start()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", default="7.21.3")
    parser.add_argument(
        "--state",
        type=Path,
        default=Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state"))
        / "chr",
    )
    parser.add_argument("--ssh-port", type=int, default=2222)
    parser.add_argument(
        "command",
        choices=["start", "stop", "fresh", "status", "ssh", "run", "scenarios"],
    )
    parser.add_argument(
        "target", nargs="?", help="RouterOS command for ssh, or scenario name for run"
    )
    args = parser.parse_args()
    if not re.fullmatch(r"7\.\d+(?:\.\d+)?(?:(?:rc|beta)\d+)?", args.version):
        parser.error("version must be a RouterOS 7 release number")
    if not 1024 <= args.ssh_port <= 65535:
        parser.error("use an unprivileged SSH port")
    scenarios = {
        path.name.replace("_", "-"): path.name
        for path in (SOURCE / "scenarios").iterdir()
        if path.is_dir() and (path / "__init__.py").exists()
    }
    if args.command == "run" and args.target not in scenarios:
        parser.error(f"choose a scenario: {', '.join(sorted(scenarios))}")
    if args.command == "scenarios":
        print("\n".join(sorted(scenarios)))
        return
    if any(character in str(args.state.resolve()) for character in ",:\n"):
        parser.error("state directory cannot contain comma, colon, or newline")
    os.umask(0o077)
    lab = Lab(args)
    with (lab.root / "lab.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if args.command in ("start", "stop", "fresh"):
            getattr(lab, args.command)()
        elif args.command == "status":
            print(
                f"CHR {args.version}: {'running' if lab.running() else 'stopped'}\nState: {lab.directory}"
            )
        elif args.command == "run":
            scenario = importlib.import_module(f"scenarios.{scenarios[args.target]}")
            scenario.experiment(lab)
        elif args.command == "ssh":
            if args.target:
                print(lab.ssh(args.target))
            else:
                if not lab.running():
                    raise RuntimeError("Lab is stopped")
                run(*lab.ssh_args())


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"Error: {error}", file=sys.stderr)
        sys.exit(1)
