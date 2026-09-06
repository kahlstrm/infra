import unittest
from unittest.mock import Mock

from lab import Lab


class ForwardTest(unittest.TestCase):
    def setUp(self):
        self.lab = Lab.__new__(Lab)
        self.lab.ssh_port = 2222
        self.lab.monitor = Mock()

    def test_removes_forward_after_scenario_failure(self):
        with self.assertRaisesRegex(RuntimeError, "experiment failed"):
            with self.lab.forward("udp", 1053, 53):
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
        with self.assertRaisesRegex(RuntimeError, "port in use"):
            with self.lab.forward("tcp", 1053, 53):
                self.fail("scenario must not run")
        self.lab.monitor.assert_called_once()

    def test_forward_cannot_replace_management_port(self):
        with self.assertRaisesRegex(ValueError, "SSH management port"):
            with self.lab.forward("tcp", 2222, 80):
                self.fail("scenario must not run")
        self.lab.monitor.assert_not_called()

    def test_validates_forward_before_sending_monitor_commands(self):
        for protocol, host_port, guest_port in [
            ("icmp", 1053, 53),
            ("udp", 53, 53),
            ("tcp", 8080, 65536),
        ]:
            with self.subTest(
                protocol=protocol, host_port=host_port, guest_port=guest_port
            ):
                with self.assertRaises(ValueError):
                    with self.lab.forward(protocol, host_port, guest_port):
                        self.fail("scenario must not run")
        self.lab.monitor.assert_not_called()


if __name__ == "__main__":
    unittest.main()
