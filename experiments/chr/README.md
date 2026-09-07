# CHR lab

A persistent, local RouterOS VM for infrastructure experiments. The lab manages
images, disks, credentials, SSH, and packet captures. Individual scenarios own
their router configuration, dependencies, probes, and results.

## Run a router

From the repository root on Linux with access to `/dev/kvm`:

```sh
nix develop .#chr
just chr start
just chr status
just chr ssh
just chr ssh '/system/resource/print'
just chr stop
```

The first start downloads MikroTik's official CHR image and creates a writable
overlay. First boot sets a random admin password, installs a dedicated SSH key,
and disables management services other than SSH. The default version is 7.21.3.
A fresh VM retains RouterOS defaults for DNS and other network services.

The VM has 512 MiB RAM, two vCPUs, and one QEMU user-mode NAT interface with
outbound Internet access. SSH binds to `127.0.0.1:2222`; it is not bridged to the
LAN. The free CHR license is sufficient and needs no MikroTik account.

`start` reuses the disk. `stop` requests an orderly ACPI shutdown and retains the
disk and evidence. `fresh` stops the VM, archives its disk and configuration, and
boots a new image of the selected version:

```sh
just chr fresh
```

Required tools are Python 3, QEMU (`qemu-system-x86_64`, `qemu-img`), OpenSSH,
curl, and just. The lifecycle commands require neither Java nor DNS tooling.
Python code uses only the standard library.

## Run an experiment

```sh
just chr scenarios
nix develop .#chr-netty
just chr start
just chr run netty-dns
```

Available scenarios:

| Name | Purpose | Documentation |
| --- | --- | --- |
| `dns-referral` | Three-query RouterOS DNS response reproduction, no Java | [README](scenarios/dns_referral/README.md) |
| `netty-dns` | Root NS caching and Vert.x/Netty DNS query-budget failures | [README](scenarios/netty_dns/README.md) |

For the minimal DNS-only scenario, use `nix develop .#chr-dns` and
`just chr run dns-referral`.

A scenario runs against the selected VM and may change its configuration. Use
`fresh` to return to RouterOS defaults between unrelated experiments. Scenarios
can open temporary localhost port forwards through the lab API; forwards are
removed when their context exits. If the controller is forcibly killed, restart
the VM to remove any surviving temporary forwards.

## Versions and state

Each version has separate disks and credentials. Stop one before starting
another on the same SSH port:

```sh
just chr stop
just chr --version 7.23.5 start
just chr --version 7.23.5 run netty-dns
just chr --version 7.23.5 stop
just chr start
```

Use `--ssh-port 2223` when starting another version concurrently. Commands for a
running VM discover its saved SSH port. Scenarios may have their own fixed ports
and should be run sequentially if those ports overlap.

Mutable state lives in `$XDG_STATE_HOME/chr` (default `~/.local/state/chr`), outside
Git. Override it with `--state /absolute/path` before the command. A state-directory
lock prevents overlapping lifecycle operations and scenario runs.

- `images/`: downloaded raw images shared by version-specific overlays.
- `<version>/`: disk, private credentials, sockets, and process metadata.
- `<version>/captures/`: one QEMU Ethernet PCAP per boot.
- `<version>/archives/`: previous disks and configuration retained by `fresh`.
- `<version>/results/<scenario>/`: scenario evidence and summaries.
- `scenarios/<scenario>/`: downloaded scenario dependencies and build artifacts.

Keep raw images with their overlays when backing up or moving the lab; overlays
contain absolute backing-image paths. Stop the VM and rebase those paths with
`qemu-img rebase -u` if relocating the state directory. Existing evidence from the
original DNS lab remains in `<version>/results/<timestamp>/`.

## Add a scenario

Create `scenarios/<name>/__init__.py` with an `experiment(lab)` function, plus its
own README, probes, and tests. Directory underscores become hyphens in the CLI;
`netty_dns` is invoked as `netty-dns`. No scenario registration change is needed
in the lab controller.

Use `lab.ssh(command)` for RouterOS configuration, and scoped forwarding for
services the experiment needs, for example:

```python
with lab.forward("tcp", 8080, 80):
    # Run the scenario's HTTP probe against 127.0.0.1:8080.
    ...
```

Keep results under `lab.directory / "results" / "<scenario>"` and downloaded
dependencies under `lab.root / "scenarios" / "<scenario>"`. Scenario-specific
setup belongs in the scenario, not in the base VM bootstrap.

Run all controller and scenario unit tests without booting a VM:

```sh
python3 -m unittest discover -s experiments/chr -p 'test_*.py' -v
```

Sources: [MikroTik CHR installation](https://manual.mikrotik.com/docs/getting-started/installation-and-upgrade/install/chr-installation/),
[CHR licensing](https://manual.mikrotik.com/docs/getting-started/routeros-licensing/chr/chr-licensing/).
