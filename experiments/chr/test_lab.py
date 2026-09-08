import json
import subprocess
import unittest
import zipfile
from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace
from unittest.mock import Mock, patch

from lab import Lab, download
from scenarios.bootstrap import verify_adoption_plan


class AdoptionPlanTest(unittest.TestCase):
    def plan(self, resource_type, actions, name="management"):
        return json.dumps({
            "resource_changes": [{
                "address": f"module.bootstrap_stationary.{resource_type}.{name}",
                "type": resource_type,
                "name": name,
                "change": {"actions": actions},
            }]
        })

    def test_accepts_unchanged_router_settings(self):
        verify_adoption_plan(self.plan("routeros_ip_address", ["no-op"]))

    def test_rejects_router_drift_before_apply(self):
        for actions in (["update"], ["create"], ["delete"], ["delete", "create"]):
            with self.subTest(actions=actions), self.assertRaisesRegex(
                RuntimeError, "routeros_ip_address.management"
            ):
                verify_adoption_plan(self.plan("routeros_ip_address", actions))

    def test_only_allows_script_file_creation(self):
        for resource_type in ("local_file", "routeros_file"):
            verify_adoption_plan(self.plan(resource_type, ["create"], "script"))
            for actions, name in (
                (["update"], "script"),
                (["delete", "create"], "script"),
                (["create"], "other"),
            ):
                with (
                    self.subTest(resource_type=resource_type, actions=actions, name=name),
                    self.assertRaises(RuntimeError),
                ):
                    verify_adoption_plan(self.plan(resource_type, actions, name))


class DownloadTest(unittest.TestCase):
    def setUp(self):
        directory = TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.destination = Path(directory.name) / "chr.img.zip"
        self.member = "chr.img"
        sleep = patch("lab.time.sleep")
        sleep.start()
        self.addCleanup(sleep.stop)

    def valid_download(self, *args):
        with zipfile.ZipFile(args[-1], "w") as archive:
            archive.writestr(self.member, b"router image")

    def test_retries_interrupted_transfer_without_caching_partial_file(self):
        def transfer(*args):
            if command.call_count == 1:
                Path(args[-1]).write_bytes(b"partial")
                raise subprocess.CalledProcessError(56, args)
            self.assertFalse(Path(args[-1]).exists())
            self.valid_download(*args)

        with patch("lab.run", side_effect=transfer) as command:
            download("https://example.test/chr.zip", self.destination, self.member)
        self.assertEqual(command.call_count, 2)
        with zipfile.ZipFile(self.destination) as archive:
            self.assertEqual(archive.read(self.member), b"router image")

    def test_retries_invalid_content_even_when_curl_succeeds(self):
        def transfer(*args):
            if command.call_count == 1:
                Path(args[-1]).write_bytes(b"not a zip")
            else:
                self.valid_download(*args)

        with patch("lab.run", side_effect=transfer) as command:
            download("https://example.test/chr.zip", self.destination, self.member)
        self.assertEqual(command.call_count, 2)

    def test_replaces_invalid_cache_and_reuses_valid_cache(self):
        self.destination.write_bytes(b"broken cache")
        with patch("lab.run", side_effect=self.valid_download) as command:
            download("https://example.test/chr.zip", self.destination, self.member)
            download("https://example.test/chr.zip", self.destination, self.member)
        command.assert_called_once()

    def test_wrong_archive_member_exhausts_retries_without_cached_files(self):
        def transfer(*args):
            with zipfile.ZipFile(args[-1], "w") as archive:
                archive.writestr("wrong.img", b"wrong image")

        with patch("lab.run", side_effect=transfer) as command:
            with self.assertRaisesRegex(RuntimeError, "valid CHR image"):
                download("https://example.test/chr.zip", self.destination, self.member)
        self.assertEqual(command.call_count, 3)
        self.assertEqual(list(self.destination.parent.iterdir()), [])

    def test_failed_extraction_does_not_leave_an_image(self):
        lab = Lab(SimpleNamespace(version="test", state=self.destination.parent, ssh_port=2222))
        with patch("lab.download") as fetch, patch("lab.run") as command:
            fetch.side_effect = lambda url, path, member: self.valid_download(str(path))
            self.member = "chr-test.img"
            with patch("lab.shutil.copyfileobj", side_effect=OSError("disk full")):
                with self.assertRaisesRegex(OSError, "disk full"):
                    lab.prepare()
        command.assert_not_called()
        self.assertFalse((lab.root / "images/chr-test.img").exists())
        self.assertFalse((lab.root / "images/chr-test.img.part").exists())


class BootstrapConsoleTest(unittest.TestCase):
    def test_repeated_password_prompt_does_not_send_password_as_command(self):
        with TemporaryDirectory() as directory:
            lab = Lab(
                SimpleNamespace(version="7.21.3", state=Path(directory), ssh_port=2222)
            )
            lab.key.with_suffix(".pub").write_text("ssh-ed25519 test")
            console = Mock()
            console.recv.side_effect = [
                b"Login:",
                b"Password:",
                b"Do you want to see the software license",
                b"new password>",
                b"new password>",
                b"repeat new password>",
                b"repeat new password>",
                b"Password changed\r\n[admin@MikroTik] >",
                *([b"\r\n[admin@chr-lab] >"] * 5),
            ]
            with (
                patch("lab.socket.socket") as socket,
                patch("lab.select.select", return_value=([console], [], [])),
            ):
                socket.return_value.__enter__.return_value = console
                lab.bootstrap()
            password = (lab.directory / "password").read_text().encode() + b"\r"
            self.assertEqual(
                sum(
                    call.args[0] == password for call in console.sendall.call_args_list
                ),
                2,
            )


class ForwardTest(unittest.TestCase):
    def setUp(self):
        self.lab = Lab.__new__(Lab)
        self.lab.ssh_port = 2222
        self.lab.monitor = Mock()

    def test_removes_forward_after_scenario_failure(self):
        with (
            self.assertRaisesRegex(RuntimeError, "experiment failed"),
            self.lab.forward("udp", 1053, 53),
        ):
            raise RuntimeError("experiment failed")
        self.assertEqual(
            [call.args[0] for call in self.lab.monitor.call_args_list],
            [
                "hostfwd_add lab udp:127.0.0.1:1053-:53",
                "hostfwd_remove lab udp:127.0.0.1:1053",
            ],
        )

    def test_failed_add_does_not_remove_an_existing_forward(self):
        self.lab.monitor.side_effect = RuntimeError("port in use")
        with (
            self.assertRaisesRegex(RuntimeError, "port in use"),
            self.lab.forward("tcp", 1053, 53),
        ):
            self.fail("scenario must not run")
        self.lab.monitor.assert_called_once()

    def test_forward_cannot_replace_management_port(self):
        with (
            self.assertRaisesRegex(ValueError, "SSH management port"),
            self.lab.forward("tcp", 2222, 80),
        ):
            self.fail("scenario must not run")
        self.lab.monitor.assert_not_called()

    def test_validates_forward_before_sending_monitor_commands(self):
        for protocol, host_port, guest_port in [
            ("icmp", 1053, 53),
            ("udp", 53, 53),
            ("tcp", 8080, 65536),
        ]:
            with (
                self.subTest(
                    protocol=protocol, host_port=host_port, guest_port=guest_port
                ),
                self.assertRaises(ValueError),
                self.lab.forward(protocol, host_port, guest_port),
            ):
                self.fail("scenario must not run")
        self.lab.monitor.assert_not_called()


if __name__ == "__main__":
    unittest.main()
