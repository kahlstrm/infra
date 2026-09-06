import unittest

from scenarios.netty_dns import probe_counts


class ProbeCountsTest(unittest.TestCase):
    def test_counts_reproduced_failures(self):
        output = (
            "server=127.0.0.1:1053 round=0 ok=12 failed=0 error=null\n"
            "server=127.0.0.1:1053 round=1 ok=0 failed=12 error=java.net.UnknownHostException: "
            "Exceeded max queries per resolve 4\n"
        )
        self.assertEqual(probe_counts(output, 2, 12), (12, 12))

    def test_rejects_missing_round(self):
        with self.assertRaisesRegex(RuntimeError, "every round"):
            probe_counts("round=0 ok=12 failed=0 error=null", 2, 12)

    def test_rejects_missing_callbacks(self):
        with self.assertRaisesRegex(RuntimeError, "incomplete round"):
            probe_counts("round=0 ok=11 failed=0 error=null", 1, 12)

    def test_rejects_reordered_rounds(self):
        with self.assertRaisesRegex(RuntimeError, "every round"):
            probe_counts(
                "round=1 ok=12 failed=0 error=null\nround=0 ok=12 failed=0 error=null",
                2,
                12,
            )

    def test_does_not_mislabel_transport_failure_as_reproduction(self):
        with self.assertRaisesRegex(RuntimeError, "Unexpected lookup failure"):
            probe_counts("round=0 ok=0 failed=12 error=Connection refused", 1, 12)


if __name__ == "__main__":
    unittest.main()
