# CHR lab

A local QEMU/RouterOS runner for bootstrap integration tests. It owns image
caching, disposable credentials, SSH access, disks, and captures. The bootstrap
scenario owns the test topology and assertions.

## Test bootstrap adoption

```sh
nix develop .#chr-bootstrap
just chr run bootstrap
```

Requires Linux with access to `/dev/kvm`. The scenario resets two disposable
CHRs using the checked-in production bootstrap scripts, adopts their resources,
then repeats after reset with retained Terraform state. See the
[scenario README](scenarios/bootstrap/README.md) for coverage and limitations.

## Inspect a standalone router

```sh
nix develop .#chr
just chr start
just chr ssh
just chr stop
```

The default version is RouterOS 7.21.3. `start` reuses its disk; `stop` retains
it; `fresh` archives the old disk and creates a clean router. Use
`just chr --version 7.23.5 start` to choose another version, stopping the old
VM first if its SSH port is in use. SSH defaults to `127.0.0.1:2222`.

Images, disks, credentials, and captures live outside Git under
`$XDG_STATE_HOME/chr` (default `~/.local/state/chr`). Override this with
`--state /absolute/path`. State is private and operations on the same directory
are locked. Keep images with their overlays when moving or backing up the lab.

The runner uses Python's standard library, QEMU, OpenSSH, and curl. Scenarios
are discovered under `scenarios/<name>/__init__.py` and expose `experiment(lab)`.
They can use `lab.ssh(command)` and `lab.forward(protocol, local_port, guest_port)`.
Keep scenario dependencies and configuration out of the shared runner.

Run Python tests without starting a VM:

```sh
python3 -m unittest discover -s experiments/chr -p 'test_*.py'
python3 -m unittest discover -s local-networking/scripts -p 'test_*.py'
```
