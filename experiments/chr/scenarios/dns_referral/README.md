# RouterOS empty AAAA response reproduction

A cached root NS response can make RouterOS answer an unrelated negative AAAA
query with root NS records and no SOA. Reproduced on CHR **7.21.3, 7.23.5 and
7.24.2** on 2026-09-06. MikroTik acknowledged the issue in a support response
shared on 2026-09-07 and intends to fix it, with no ETA or target version.

## Run

From the repository root, on Linux with KVM:

```sh
nix develop .#chr-dns
just chr start
just chr run dns-referral
```

The scenario configures the isolated router to use Cloudflare 1.1.1.1, flushes
its DNS cache, then runs these three queries through a temporary localhost port:

```sh
dig @127.0.0.1 -p 1053 s3.eu-west-1.amazonaws.com AAAA
dig @127.0.0.1 -p 1053 . NS
dig @127.0.0.1 -p 1053 s3.eu-west-1.amazonaws.com AAAA
```

Port 1053 is forwarded only while the scenario runs. To reproduce independently,
replace `@127.0.0.1 -p 1053` with `@CHR_IP` and start from a clean DNS cache with
`/ip/dns/set servers=1.1.1.1 allow-remote-requests=yes use-doh-server=""` and
`/ip/dhcp-client/set [find] use-peer-dns=no`.

| AAAA response | Status | Answers | Authority |
| --- | --- | --- | --- |
| Before `. NS` | NOERROR | 0 | Empty |
| After `. NS` | NOERROR | 0 | 13 root NS records, no SOA |

The hostname must still have A records and no AAAA records; this is a live DNS
dependency. Check that prerequisite with `dig @1.1.1.1 s3.eu-west-1.amazonaws.com
AAAA` if results change. The command reports whether the behavior reproduced;
a completed run is not an assertion that a RouterOS version is fixed or broken.

The scenario saves raw replies, router settings and a summary under
`~/.local/state/chr/<version>/results/dns-referral/<timestamp>/`. It removes its
forwards and flushes the lab cache on exit. DNS settings remain configured;
use `just chr fresh` between unrelated scenarios. Production routers and the host
resolver are untouched.

## What we learned

RFC 2308 §2.2 distinguishes NODATA from a referral using SOA presence or NS
absence. The primed reply has the shape of a referral. A 7.24.2 capture showed
Cloudflare returning SOA records that RouterOS omitted.

- Netty 4.1.104.Final and Vert.x 4.5.1 failed some subsequent lookups with a
  four-query budget. Direct Netty reproduced it without Vert.x or concurrent
  application requests. The tested default 16-query Netty configuration and
  Node/Go clients succeeded. See the [Netty scenario](../netty_dns/README.md).
- Caching root-server addresses made RouterOS include actual IPv4 glue, but did
  not fix the four-query Netty failures.
- Chrome 152 on Linux completed the tested requests, sometimes falling back to
  the system resolver. Live GitHub/Steam tests did not establish a consistent
  slowdown; occasional DNS delays are not enough to attribute causation.
- A RouterOS static-A-record control did not show the same response change.
  These observations do not establish effects on every hostname or client.

The submitted evidence bundle is retained outside Git at
`~/.local/state/chr/reports/mikrotik-dns-20260906.zip`. Detailed investigation
notes and the prepared report/support response are archived alongside it in
`repository-notes-20260907/`; raw glue and browser runs remain under the lab's
`results/` directory. Keep representative evidence outside Git.

Sources: [RFC 2308 §2.2](https://www.rfc-editor.org/rfc/rfc2308.html#section-2.2).
See the [lab README](../../README.md) for lifecycle commands.
