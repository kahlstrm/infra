# Vert.x/Netty DNS scenario

Test whether caching root NS records in RouterOS changes negative DNS replies
and causes Vert.x resolution to exhaust its query budget. This standalone probe
uses the [generic CHR lab](../../README.md) and has no application dependency.

## Run

From the repository root:

```sh
nix develop .#chr-netty
just chr start
just chr run netty-dns
```

To compare another RouterOS version:

```sh
just chr stop
just chr --version 7.23.5 start
just chr --version 7.23.5 run netty-dns
```

The `chr-netty` shell extends the generic lab tools with dig and Java/Javac 21.
The first run downloads pinned Java libraries from Maven Central. This scenario
requires Internet access and queries the public S3 hostname; it is not hermetic.

## Setup and cleanup

The scenario temporarily forwards localhost TCP/UDP port 1053 to guest port 53.
It configures DNS to forward directly to `1.1.1.1`, `1.0.0.1`, `8.8.8.8`, and
`8.8.4.4`, enables remote DNS requests, sets a 40 MiB cache, and disables DoH and
DHCP-provided DNS. This prevents the host's router from becoming an implicit DNS
upstream. Run on a fresh VM to exclude existing adlists and static DNS records.

The scenario flushes its DNS cache on exit and removes the temporary port
forwards. The configured DNS settings remain in the lab VM. Use `just chr fresh`
to restore a generic RouterOS image before an unrelated experiment. It does not
modify the host's resolver configuration or the physical routers.

## Probe

1. Flush the cache, capture S3 A/AAAA replies, and run the Java probe.
2. Issue one `. NS` query, then capture replies and run a new Java probe.
3. Flush again and repeat to test recovery with a new Java process.

Each probe uses Vert.x 4.5.1 and Netty 4.1.104.Final, `maxQueries=4`, and four
rounds of 12 concurrent lookups separated by six seconds. This crosses the
observed five-second S3 A-record TTL. The dependency classpath contains one
version per library. Netty DNS debug logging records referral destinations.

Baseline and recovery must pass. Query-budget failures in the primed phase are
an experimental result. A fixed RouterOS version may pass all three phases.
Missing callbacks, incomplete rounds, command failures, and unexpected error
types fail the run. The test does not establish recovery of an already affected,
long-lived application process.

## Evidence

Results are saved under
`~/.local/state/chr/<version>/results/netty-dns/<UTC timestamp>/` (or the selected
state directory). Each run records raw A/AAAA replies, the root query, router
settings, cache contents, Java results, Netty logs, and `summary.txt`.

Guest traffic is in the lab's per-boot PCAP. Netty's direct Internet queries run
on the host and appear in its logs, not the guest PCAP.

Observed on 2026-09-06 with the commands above:

| RouterOS | Fresh cache | After one root NS query | After flush, new Java process |
| --- | --- | --- | --- |
| 7.21.3 | 48 succeeded, 0 failed | 24 succeeded, 24 failed | 48 succeeded, 0 failed |
| 7.23.5 | 48 succeeded, 0 failed | 24 succeeded, 24 failed | 48 succeeded, 0 failed |

Failures reported `Exceeded max queries per resolve 4`. A root NS query changed
the empty AAAA response from an empty authority section to 13 root NS records.
No root-server address was manually seeded. Thus the root query alone triggered
the tested behavior, and 7.23.5 did not resolve it. Flushing restored these fresh
client runs, but another root NS query can trigger it again.

These counts describe short runs against the public S3 hostname; they do not
establish a six-day outage or a permanent failure within a client process.

Source: [RFC 2308, negative DNS responses](https://www.rfc-editor.org/rfc/rfc2308.html#section-2.2).
