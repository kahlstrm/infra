"""Reset two disposable routers using the checked-in production bootstrap scripts."""

import os
import re
import shutil
import socket
import subprocess
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from types import SimpleNamespace

from lab import SOURCE, Lab, run

REPO = SOURCE.parents[1]


def port():
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        return listener.getsockname()[1]


class BootstrapLab(Lab):
    def __init__(self, parent, root, name, transit_port, listen):
        self.name = name
        self.transit_port = transit_port
        self.listen = listen
        self.address = "10.1.1.1" if name == "stationary" else "10.10.10.1"
        self.prefix = self.address.rsplit(".", 1)[0]
        self.https_port = port()
        super().__init__(
            SimpleNamespace(version=parent.version, state=root / name, ssh_port=port())
        )
        images = self.root / "images"
        (parent.root / "images").mkdir(exist_ok=True)
        if not images.exists():
            images.symlink_to(parent.root / "images", target_is_directory=True)

    def network_args(self, capture):
        args = []
        # The first NIC provides access to the factory image's ether1 DHCP client.
        # The reset wrapper maps it to the RB5009 LAN port ether2.
        for index in range(1, 10):
            ident = "lab" if index == 1 else f"port{index}"
            if index == 1:
                backend = (
                    f"user,id={ident},net={self.prefix}.0/24,host={self.prefix}.254,"
                    f"dhcpstart={self.prefix}.200,"
                    f"hostfwd=tcp:127.0.0.1:{self.ssh_port}-{self.prefix}.200:22,"
                    f"hostfwd=tcp:127.0.0.1:{self.https_port}-{self.address}:443"
                )
            elif index == 2:
                mode = "listen" if self.listen else "connect"
                backend = f"socket,id={ident},{mode}=127.0.0.1:{self.transit_port}"
            elif index == 8:
                backend = f"user,id={ident},net=192.0.2.0/24"
            else:
                backend = f"hubport,id={ident},hubid={index}"
            args += [
                "-netdev",
                backend,
                "-device",
                f"virtio-net-pci,netdev={ident},mac=52:54:00:00:{1 if self.listen else 2:02x}:{index:02x}",
            ]
        args += ["-object", f"filter-dump,id=capture,netdev=lab,file={capture}"]
        return args

    def upload(self, path, name):
        args = self.ssh_args()
        args[0] = "scp"
        args[args.index("-p")] = "-P"
        destination = args.pop()
        run(
            *args,
            "-O",
            str(path),
            f"{destination}:{name}",
            capture_output=True,
            timeout=30,
        )
        # SCP can acknowledge before RouterOS exposes the file to scripting.
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            try:
                size = self.ssh(f':put [/file get [find name="{name}"] size]').strip()
            except RuntimeError:
                size = ""
            if size == str(path.stat().st_size):
                return
            time.sleep(0.5)
        raise RuntimeError(f"{self.name}: upload not visible: {name}")

    def reset_bootstrap(self):
        script = REPO / "local-networking/bootstrap/generated" / f"{self.name}.rsc"
        shutil.copyfile(script, self.directory / "bootstrap.rsc")
        script = self.directory / "bootstrap.rsc"
        self.upload(script, "bootstrap.rsc")
        wrapper = self.directory / "reset.rsc"
        wrapper.write_text(
            ":delay 5s\n"
            "/interface ethernet set [find default-name=ether1] name=temporary-lan\n"
            "/interface ethernet set [find default-name=ether2] name=ether1\n"
            "/interface ethernet set [find default-name=ether1] name=ether2\n"
            "/interface ethernet set [find default-name=ether9] name=sfp-sfpplus1\n"
            "/ip dhcp-client remove [find]\n"
            "/import file-name=bootstrap.rsc\n"
        )
        # Create the reset hook through RouterOS itself. A newly SCP-uploaded
        # file can be readable while still absent from run-after-reset's index.
        contents = (
            wrapper.read_text()
            .replace("\\", "\\\\")
            .replace('"', '\\"')
            .replace("\n", "\\n")
        )
        self.ssh(
            "/file remove [find name=reset.rsc]; /file remove [find name=boostrap.txt]"
        )
        self.ssh(f'/file add name=reset.rsc type=file contents="{contents}"')
        print(f"{self.name}: resetting into production bootstrap", flush=True)
        try:
            self.ssh(
                "/system reset-configuration no-defaults=yes keep-users=yes skip-backup=yes run-after-reset=reset.rsc"
            )
        except subprocess.CalledProcessError as error:
            # Reset may close SSH before it returns an exit status. Completion
            # is determined by the saved marker and post-reboot checks below.
            output = error.stdout + error.stderr
            (self.directory / "reset-request.log").write_text(output)
            if "input does not match" in output:
                raise RuntimeError(
                    f"{self.name}: RouterOS rejected reset.rsc"
                ) from error
        self.monitor(f"hostfwd_remove lab tcp:127.0.0.1:{self.ssh_port}")
        self.monitor(f"hostfwd_add lab tcp:127.0.0.1:{self.ssh_port}-{self.address}:22")
        time.sleep(10)
        (self.directory / "known_hosts").unlink(missing_ok=True)
        deadline = time.monotonic() + 240
        while time.monotonic() < deadline:
            serial_log = self.directory / "serial.log"
            if (
                serial_log.exists()
                and "error while running run-after-reset script"
                in serial_log.read_text(errors="replace")
            ):
                raise RuntimeError(
                    f"{self.name}: reset script failed; see {serial_log}"
                )
            try:
                output = self.ssh(
                    ':put [/file get [find name="boostrap.txt"] contents]'
                )
                if "bootstrap_script_finished" in output:
                    # The script sets this RAM-only global; its absence
                    # confirms the bootstrap's final reboot has happened.
                    if (
                        self.ssh(
                            ':put [:len [/system script environment find where name="isLocalBridgeCreated"]]'
                        ).strip()
                        != "0"
                    ):
                        time.sleep(1)
                        continue
                    (self.directory / "bootstrap.log").write_text(output)
                    print(
                        f"{self.name}: bootstrap completed, management reachable",
                        flush=True,
                    )
                    return
            except (subprocess.SubprocessError, RuntimeError):
                pass
            time.sleep(3)
        raise RuntimeError(f"{self.name}: bootstrap failed; inspect {self.directory}")

    def check(self, command, expected, label):
        output = self.ssh(command).strip()
        with (self.directory / "checks.txt").open("a") as evidence:
            evidence.write(f"{label}\n{command}\n{output}\n\n")
        if output != expected:
            raise RuntimeError(
                f"{self.name}: {label}: expected {expected!r}, got {output!r}"
            )
        print(f"{self.name}: PASS {label}", flush=True)

    def adopt(self, recovery=False):
        directory = self.directory / "terraform"
        directory.mkdir(exist_ok=True)
        source = Path(__file__).with_name("adoption.tftpl").read_text()
        values = {
            "PROVIDER_VERSION": re.search(
                r'provider "registry.terraform.io/terraform-routeros/routeros" \{\s+version\s+= "([^"]+)"',
                (REPO / "local-networking/.terraform.lock.hcl").read_text(),
            )[1],
            "HTTPS_PORT": str(self.https_port),
            "SITE": self.name,
            "MODULES": os.path.relpath(REPO / "local-networking/modules", directory),
            "BOOTSTRAP_FILE": str(
                REPO / "local-networking/bootstrap/generated" / f"{self.name}.rsc"
            ),
            "POOL_RANGE": f"{self.prefix}.100-{self.prefix}.199",
        }
        for key, value in values.items():
            source = source.replace(key, value)
        (directory / "main.tf").write_text(source)
        shutil.copyfile(
            REPO / "local-networking/.terraform.lock.hcl",
            directory / ".terraform.lock.hcl",
        )
        env = dict(
            os.environ,
            TF_VAR_password=(self.directory / "password").read_text(),
            TF_IN_AUTOMATION="1",
        )

        def terraform(label, *args):
            result = subprocess.run(
                [shutil.which("tofu") or "terraform", args[0], "-no-color", *args[1:]],
                cwd=directory,
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )
            (directory / f"{label}.log").write_text(result.stdout + result.stderr)
            if result.returncode:
                raise RuntimeError(
                    f"{self.name}: Terraform {label} failed; see {directory / (label + '.log')}"
                )
            return result.stdout

        terraform("init", "init", "-backend=false")
        importer = REPO / "local-networking/scripts/adopt-bootstrap.py"
        command = [
            "python3",
            str(importer),
            "--terraform",
            shutil.which("tofu") or "terraform",
            "--directory",
            str(directory),
            "--router",
            self.name,
        ]
        for label, flags in [
            ("preview", []),
            ("adopt", ["--apply"]),
            ("repeat", ["--apply"]),
        ]:
            result = subprocess.run(
                command + flags, env=env, capture_output=True, text=True, check=False
            )
            (directory / f"{label}.log").write_text(result.stdout + result.stderr)
            if result.returncode:
                raise RuntimeError(
                    f"{self.name}: importer {label} failed; see {directory / (label + '.log')}"
                )
            if recovery and label == "adopt" and "rebind " not in result.stdout:
                raise RuntimeError(
                    f"{self.name}: reset did not exercise stale binding repair"
                )
            if label == "repeat" and "No state changes needed." not in result.stdout:
                raise RuntimeError(f"{self.name}: repeat adoption was not a no-op")
        # Exercise the actual production resources adopted by this command.
        # Other site services remain outside this bootstrap-focused scenario.
        result = subprocess.run(
            [shutil.which("tofu") or "terraform", "console", "-no-color"],
            cwd=directory,
            env=env,
            input='jsonencode([for b in module.bootstrap_adoption.bindings : b.address if b.router == "'
            + self.name
            + '"])\n',
            capture_output=True,
            text=True,
            check=True,
        )
        addresses = run(
            "jq", "-r", "fromjson | .[]", input=result.stdout, capture_output=True
        ).stdout.splitlines()
        targets = [f"-target={address}" for address in addresses]
        terraform("plan", "plan", *targets, "-out=adopt.tfplan")
        plan = terraform("show", "show", "-json", "adopt.tfplan")
        run(
            "jq",
            "-e",
            'all(.resource_changes[]; (.change.actions | index("delete") | not) and (.type == "routeros_file" or (.change.actions | index("create") | not)))',
            input=plan,
            capture_output=True,
        )
        terraform("apply", "apply", "adopt.tfplan")
        terraform("settled", "plan", *targets, "-detailed-exitcode")
        print(
            f"{self.name}: PASS adoption, repeat no-op and empty targeted plan",
            flush=True,
        )

    def verify(self):
        peer = "10.10.10.1" if self.listen else "10.1.1.1"
        for name, address in [("stationary", "10.1.1.1"), ("kuberack", "10.10.10.1")]:
            self.check(
                f':put [:resolve "{name}.networking.kalski.xyz" type=ipv4]',
                address,
                f"DNS A record for {name}",
            )
        dns_port = port()
        self.monitor(f"hostfwd_add lab udp:127.0.0.1:{dns_port}-{self.address}:53")
        try:
            for name, address in [
                ("stationary", "10.1.1.1"),
                ("kuberack", "10.10.10.1"),
            ]:
                result = run(
                    "dig",
                    "@127.0.0.1",
                    "-p",
                    str(dns_port),
                    f"{name}.networking.kalski.xyz",
                    "A",
                    "+short",
                    "+time=2",
                    "+tries=1",
                    capture_output=True,
                )
                if result.stdout.strip() != address:
                    raise RuntimeError(
                        f"{self.name}: external DNS query for {name} failed: {result.stdout}"
                    )
            print(f"{self.name}: PASS DNS queries from outside the router", flush=True)
        finally:
            self.monitor(f"hostfwd_remove lab udp:127.0.0.1:{dns_port}")
        self.check(
            f':local received 0; :foreach reply in=[/ping address={peer} src-address={self.address} count=3 interval=200ms as-value] do={{:if ([:typeof ($reply->"time")] != "nil") do={{:set received ($received + 1)}}}}; :put $received',
            "3",
            "bidirectional routed IPv4 management",
        )
        self.check(
            ":put [/ip service get www-ssl disabled]",
            "false",
            "HTTPS management enabled",
        )
        self.check(
            ":put [/certificate get [find name=self] private-key]",
            "true",
            "HTTPS certificate has private key",
        )
        (self.directory / "export.rsc").write_text(self.ssh("/export terse"))


def experiment(parent):
    required = (
        "qemu-system-x86_64",
        "qemu-img",
        "ssh",
        "scp",
        "ssh-keygen",
        "curl",
        "dig",
        "jq",
    )
    missing = [command for command in required if not shutil.which(command)]
    if missing or not (shutil.which("tofu") or shutil.which("terraform")):
        raise RuntimeError(
            "Use nix develop .#chr-bootstrap to provide the test dependencies"
        )
    if not os.access("/dev/kvm", os.R_OK | os.W_OK):
        raise RuntimeError("Bootstrap E2E requires read/write access to /dev/kvm")
    root = parent.root / "bootstrap" / str(time.time_ns())
    root.mkdir(parents=True)
    print(f"Bootstrap E2E evidence: {root}", flush=True)
    transit = port()
    routers = [
        BootstrapLab(parent, root, name, transit, index == 0)
        for index, name in enumerate(("stationary", "kuberack"))
    ]
    try:
        for router in routers:
            router.start()
        with ThreadPoolExecutor(max_workers=2) as executor:
            list(executor.map(lambda router: router.reset_bootstrap(), routers))
        for router in routers:
            router.verify()
            router.adopt()
            router.verify()
        with ThreadPoolExecutor(max_workers=2) as executor:
            list(executor.map(lambda router: router.reset_bootstrap(), routers))
        for router in routers:
            # Reset can reuse IDs. Recreate DNS entries to guarantee stale bindings.
            router.ssh(
                ":foreach id in=[/ip dns static find] do={:local n [/ip dns static get $id name]; :local t [/ip dns static get $id type]; :local a [/ip dns static get $id address]; :local d [/ip dns static get $id disabled]; /ip dns static remove $id; /ip dns static add name=$n type=$t address=$a disabled=$d}"
            )
            router.adopt(recovery=True)
            router.verify()
        print(
            "PASS: bootstrap adoption and recovery with retained state after reset",
            flush=True,
        )
    finally:
        errors = []
        for router in reversed(routers):
            try:
                router.stop()
            except (OSError, RuntimeError, subprocess.SubprocessError) as error:
                errors.append(str(error))
        if errors:
            raise RuntimeError("Could not stop all lab routers: " + "; ".join(errors))
