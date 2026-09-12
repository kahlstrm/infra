# Network diagnostic journal

Times: Europe/Helsinki. Rates: Mbps down/up unless stated otherwise.
Keep entries to conditions, findings and next steps; raw data stays outside Git.

## Baseline

Pannu (wired) → stationary RB5009 → Sagemcom FAST3896. WAN ether8: 1 Gbps;
LAN uplink: 10 Gbps; ether1 transit to kuberack: 2.5 Gbps. CAKE baseline: outer
800/80, internal bandwidth zero. LAN-to-LAN qualifies for FastTrack; WAN does not.

## September 10 — coax replacement

Cable and splitter replaced ~22:29–22:33 without reboot. By September 12 morning,
uncorrectables remained at 69,761,355; none added over 24 hours. SNR: 41–43 dB.

## September 11–12 — public sweep

Hostkey/Worldstream; 36 settings × five rounds. Each trial: 15s idle, 5s warm-up,
60s simultaneous load, eight download/four upload streams. Separate capacity
checks bypassed CAKE; each trial restored 800/80 afterward.

Completed 180/180 at September 12 10:16:52: 129 near both caps, 50 underloaded,
one unassessed. Underloaded results cannot establish successful queue control.
At the 164-trial checkpoint, five 600/50 runs had Google p95 10.3–15.3 ms,
peak 32.3 ms and zero lost probes. Five 800/60 runs: p95 12.5–19.1 ms,
peak 33.9 ms, two lost probes. Final ranking pending.

Data on pannu: `~/.local/state/cake-sweep/`.

## September 12 — private sweep and bottleneck checks

Poenttoe (`head.kalski.xyz`); five rounds of 600/50, 700/70, 800/60, 800/80,
900/90, same load method; 250 GB estimate budget. Started 10:33:13, no overlap
with public sweep. Currently paused for router testing.

- Separate capacity: 490/82. First simultaneous trials: 489/21 and 484/15;
  Google p95 259/293 ms, one lost probe per 335; router p95 ~1 ms.
- Pannu → public servers, separate directions, CAKE bypassed: 414–417/84–86.
- Poenttoe → Hostkey, separate: 827 receive / 938 send; → Worldstream:
  receive busy, 3511 send. Poenttoe has no fixed ~490 Mbps sending ceiling.
- Other local traffic during one check: ~0.04/0.03 versus test ~504/43.
- Router later forwarded ~694/48; busiest sampled core 61%. No Ethernet errors.
  This excludes a fixed 490 Mbps ceiling, not transient router saturation.
- Modem-side cable change did not change router WAN: ether8 remains 1 Gbps.

Data: pannu `~/.local/state/cake-validation/` and
`~/.local/state/cake-public-recheck-1789198953/`; poenttoe
`~/.local/state/cake-endpoint-check-1789199134/`.

## Next — routed LAN test

Pannu ↔ w1 behind kuberack; separate and simultaneous load, both routers' per-core
CPU. Verify route, link speeds and FastTrack. This will not reproduce WAN CAKE.
Minimal Nix image built, smoke-tested and pushed to Harbor; ArgoCD manifests
passed admission dry runs. Awaiting merge/sync; no endpoint deployed or test run.
