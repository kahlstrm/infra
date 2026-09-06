"""Capture DNS replies and compare fresh, primed, and flushed CHR caches."""

from datetime import datetime, timezone
from pathlib import Path
import re
import subprocess

from lab import download, run


SOURCE = Path(__file__).resolve().parent
DNS_PORT = 1053

HOST = "s3.eu-west-1.amazonaws.com"


def classpath(root):
    libraries = root / "libraries"
    libraries.mkdir(exist_ok=True)
    dependencies = [("io.vertx", "vertx-core", "4.5.1")]
    dependencies += [
        ("io.netty", "netty-" + module, "4.1.104.Final")
        for module in (
            "common",
            "buffer",
            "transport",
            "resolver",
            "codec",
            "codec-dns",
            "handler",
            "handler-proxy",
            "codec-http",
            "codec-http2",
            "codec-socks",
            "resolver-dns",
            "transport-native-unix-common",
        )
    ]
    dependencies += [
        ("com.fasterxml.jackson.core", "jackson-" + module, "2.16.1")
        for module in ("core", "annotations", "databind")
    ]
    jars = []
    for group, artifact, version in dependencies:
        jar = libraries / f"{artifact}-{version}.jar"
        download(
            f"https://repo.maven.apache.org/maven2/{group.replace('.', '/')}/{artifact}/{version}/{jar.name}",
            jar,
        )
        jars.append(str(jar))
    classes = root / "classes"
    classes.mkdir(exist_ok=True)
    cp = ":".join(jars)
    run("javac", "-cp", cp, "-d", str(classes), str(SOURCE / "DnsProbe.java"))
    return str(classes) + ":" + cp


def probe_counts(output, rounds, burst):
    rows = re.findall(r"round=(\d+) ok=(\d+) failed=(\d+) error=(.*)", output)
    if len(rows) != rounds or [int(row[0]) for row in rows] != list(range(rounds)):
        raise RuntimeError("Java probe did not complete every round")
    totals = [0, 0]
    for _, ok, failed, error in rows:
        ok, failed = int(ok), int(failed)
        if ok + failed != burst:
            raise RuntimeError("Java probe returned an incomplete round")
        if failed and "Exceeded max queries per resolve 4" not in error:
            raise RuntimeError(f"Unexpected lookup failure: {error}")
        totals[0] += ok
        totals[1] += failed
    return tuple(totals)


def dig(lab, destination, name, record):
    output = run(
        "dig",
        "@127.0.0.1",
        "-p",
        str(DNS_PORT),
        name,
        record,
        "+time=3",
        "+tries=1",
        capture_output=True,
        timeout=10,
    ).stdout
    destination.write_text(output)
    if "status: NOERROR" not in output:
        raise RuntimeError(f"DNS query failed; inspect {destination}")
    return output


def experiment(lab, rounds=4, burst=12):
    with lab.forward("tcp", DNS_PORT, 53), lab.forward("udp", DNS_PORT, 53):
        lab.ssh("/ip/dhcp-client/set [find] use-peer-dns=no")
        lab.ssh(
            "/ip/dns/set servers=1.1.1.1,1.0.0.1,8.8.8.8,8.8.4.4 "
            'allow-remote-requests=yes cache-size=40960KiB verify-doh-cert=yes use-doh-server=""'
        )
        return compare_caches(lab, rounds, burst)


def compare_caches(lab, rounds, burst):
    if not lab.running():
        raise RuntimeError("Lab is stopped; run start first")
    dependency_root = lab.root / "scenarios" / "netty-dns"
    dependency_root.mkdir(parents=True, exist_ok=True)
    cp = classpath(dependency_root)
    result = (
        lab.directory
        / "results"
        / "netty-dns"
        / datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
    )
    result.mkdir(parents=True)
    print(f"Results: {result}", flush=True)
    (result / "router.txt").write_text(
        lab.ssh("/system/resource/print; /ip/dns/print; /ip/dns/adlist/print")
    )
    summary = []
    reproduced = False
    try:
        for phase in ("baseline", "root-ns", "flushed"):
            if phase == "root-ns":
                dig(lab, result / "root-query.txt", ".", "NS")
            else:
                lab.ssh("/ip/dns/cache/flush")
            for record in ("A", "AAAA"):
                dig(lab, result / f"{phase}-{record}.txt", HOST, record)
            (result / f"{phase}-cache.txt").write_text(
                lab.ssh("/ip/dns/cache/all/print detail")
            )
            logging = result / f"{phase}-logging.properties"
            logging.write_text(
                "handlers=java.util.logging.FileHandler\n.level=INFO\n"
                f"java.util.logging.FileHandler.pattern={result / (phase + '-netty.log')}\n"
                "java.util.logging.FileHandler.formatter=java.util.logging.SimpleFormatter\n"
                "java.util.logging.FileHandler.level=ALL\nio.netty.resolver.dns.level=FINE\n"
            )
            process = subprocess.run(
                [
                    "java",
                    f"-Djava.util.logging.config.file={logging}",
                    "-cp",
                    cp,
                    "DnsProbe",
                    f"127.0.0.1:{DNS_PORT}",
                    str(rounds),
                    str(burst),
                ],
                text=True,
                capture_output=True,
                timeout=rounds * 40,
            )
            (result / f"{phase}-java.txt").write_text(process.stdout + process.stderr)
            process.check_returncode()
            ok, failed = probe_counts(process.stdout, rounds, burst)
            if phase == "root-ns":
                reproduced = failed > 0
            line = f"{phase}: {ok} succeeded, {failed} failed"
            print(line, flush=True)
            summary.append(line)
            (result / "summary.txt").write_text("\n".join(summary) + "\n")
            if phase != "root-ns" and failed:
                raise RuntimeError(
                    f"{phase} must resolve successfully; inspect {result}"
                )
        message = (
            "Query-budget failure reproduced"
            if reproduced
            else "Query-budget failure not reproduced in this run"
        )
        summary.append(message)
        (result / "summary.txt").write_text("\n".join(summary) + "\n")
        print(message)
    finally:
        lab.ssh("/ip/dns/cache/flush")
    return result
