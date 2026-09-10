#!/usr/bin/env python3
"""Run WAN alert scenarios with promtool and receiver checks with amtool; requires PyYAML."""

import argparse
from pathlib import Path
import subprocess
import tempfile

import yaml


MANIFESTS = Path(__file__).resolve().parents[1] / "manifests" / "monitoring"
METRIC = "mktxp_netwatch_icmp_loss_percent"


def read_manifest(name, loader=yaml.SafeLoader):
    return yaml.load((MANIFESTS / name).read_text(), Loader=loader)


def scenario(name, values, warning=False, critical=False, eval_time="20m"):
    return {
        "name": name,
        "interval": "30s",
        "input_series": [
            {
                "series": f'{METRIC}{{routerboard_name="stationary",name="cloudflare-dns"}}',
                "values": " ".join(map(str, values)),
            },
            {
                "series": f'{METRIC}{{routerboard_name="kuberack",name="cloudflare-dns"}}',
                "values": "0+0x80",
            },
        ],
        "promql_expr_test": [
            {
                "expr": f'ALERTS{{alertname="{alert}",alertstate="firing"}}',
                "eval_time": eval_time,
                "exp_samples": [
                    {
                        "labels": f'ALERTS{{alertname="{alert}",alertstate="firing",'
                        f'severity="{severity}",routerboard_name="stationary",name="cloudflare-dns"}}',
                        "value": 1,
                    }
                ] if firing else [],
            }
            for alert, severity, firing in [
                ("WanPacketLoss", "warning", warning),
                ("WanPacketLossCritical", "critical", critical),
            ]
        ],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--promtool", default="promtool")
    parser.add_argument("--amtool", default="amtool")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory() as directory:
        directory = Path(directory)
        rules = directory / "rules.yaml"
        rules.write_text(yaml.safe_dump(read_manifest("prometheusrule-wan-loss.yaml")["spec"]))
        tests = directory / "tests.yaml"
        tests.write_text(yaml.safe_dump({
            "rule_files": [str(rules)],
            "evaluation_interval": "30s",
            "tests": [
                scenario("healthy", [0] * 61),
                scenario("single bad batch", [0] * 20 + [20] + [0] * 40, eval_time="12m"),
                scenario("recurring moderate loss", [0, 5] * 31, warning=True),
                scenario("recurring severe loss", [0, 30] * 31, warning=True, critical=True),
                scenario("warning threshold is strict", [2] * 61),
                scenario("critical threshold is strict", [10] * 61, warning=True),
                scenario("pending does not fire immediately", [20] * 61, eval_time="1m"),
                scenario("sustained severe loss", [20] * 61, warning=True, critical=True),
                scenario("recovery", [20] * 21 + [0] * 60, eval_time="25m"),
                scenario("absent probe", ["_"] * 61),
                scenario("stale batch cannot trigger warning", [0] * 20 + [20, "stale"] + ["_"] * 40, eval_time="18m"),
                scenario("stale batch cannot trigger critical", [0] * 20 + [100, "stale"] + ["_"] * 40, eval_time="12m30s"),
                scenario("staleness clears active loss alerts", [20] * 21 + ["stale"] + ["_"] * 40, eval_time="11m"),
                scenario("stale probe ages out", [20] * 21 + ["stale"] + ["_"] * 60, eval_time="25m"),
            ],
        }))
        subprocess.run([args.promtool, "check", "rules", str(rules)], check=True)
        subprocess.run([args.promtool, "test", "rules", str(tests)], check=True)

        # Exercise the CRD matchers with Alertmanager, using receivers without transports.
        routes = []
        for severity in ("critical", "warning"):
            route = read_manifest(
                f"alertmanagerconfig-telegram-{severity}.yaml", loader=yaml.BaseLoader
            )["spec"]["route"]
            routes.append({
                "receiver": route["receiver"],
                "matchers": [
                    f'{m["name"]}{m["matchType"]}"{m["value"]}"' for m in route["matchers"]
                ],
                "continue": True,
            })
        config = directory / "alertmanager.yaml"
        config.write_text(yaml.safe_dump({
            "route": {"receiver": "null", "routes": routes},
            "receivers": [{"name": name} for name in ("null", "telegram-warning", "telegram-critical")],
        }))
        for alert, severity, receiver in [
            ("WanPacketLoss", "warning", "telegram-warning"),
            ("WanPacketLossCritical", "critical", "telegram-critical"),
            ("TargetDown", "warning", "telegram-warning"),
            ("UnlistedWarning", "warning", "null"),
            ("WanPacketLoss", "info", "null"),
        ]:
            subprocess.run([
                args.amtool, "config", "routes", "test", f"--config.file={config}",
                f"--verify.receivers={receiver}", f"alertname={alert}",
                f"severity={severity}", "namespace=monitoring",
            ], check=True)


if __name__ == "__main__":
    main()
