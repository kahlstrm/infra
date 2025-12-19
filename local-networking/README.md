# Local Networking

This manages the MikroTik routers that provide redundant connectivity between the portable kuberack and stationary infrastructure.

## Network Setup

The network is composed of two main logical networks, connected by a 2.5Gbps interconnect when docked.

- **Kuberack LAN**: `10.10.10.0/24` (portable stack on the RB5009 + CRS305 switch)
- **Stationary LAN**: `10.1.1.0/24` (stationary stack; single gateway/DHCP on the stationary router at `10.1.1.1`)
- **ZeroTier VPN**: `10.255.255.0/24` (for site-to-site connectivity when separated)

### Network Diagram

```mermaid
graph TB
    subgraph "Kuberack (Portable)"
        WAN1[Internet WAN 1]
        RB5009[RB5009<br/>Gateway 10.10.10.1]
        CRS305[CRS305<br/>PoE-powered Switch]
        K8S[Talos/Kubernetes cluster<br/>10.10.10.0/24]

        WAN1 -- "ether8" --> RB5009
        RB5009 -- "PoE" --> CRS305
        CRS305 --> K8S
    end

    subgraph "Stationary"
        WAN2[Internet WAN 2]
        RB5009S[RB5009UGS<br/>Stationary Gateway 10.1.1.1]
        CRS310[CRS310<br/>Managed Switch]
        POESWITCH[8-port 2.5G PoE Switch]
        U7[U7 Pro Wall AP]
        RPI4[RPi 4<br/>Home Assistant + Unifi]
        PANNU[pannu<br/>10.1.1.10]
        ZIMA[Zimaboard 2]
        JETKVM[JetKVM<br/>10.1.1.11]

        WAN2 -- "ether1 (2.5G)" --> RB5009S
        RB5009S -- "SFP+" --> CRS310
        RB5009S --> JETKVM
        CRS310 -- "SFP+" --> POESWITCH
        POESWITCH -- "PoE" --> U7
        POESWITCH -- "PoE" --> RPI4
        CRS310 --> PANNU
        CRS310 --> ZIMA
    end

    RB5009 -. "ether1\n10.254.254.1/30" .-> |"transit link"| RB5009S
    RB5009S -. "ether2\n10.254.254.2/30" .-  RB5009
    RB5009 <-.->|ZeroTier when separated| RB5009S
```

## How It Works

_Note: The following describes the target architecture for the network. The implementation is ongoing and details are subject to change._

This network is designed for high performance when docked and graceful reachability when separated, without VRRP complexity.

### Docked (Normal High-Performance Operation)

- **Stationary Gateway**: The RB5009UGS is the sole gateway/DHCP/DNS for `10.1.1.0/24` (`10.1.1.1`).
- **Transit Link**: Dedicated point-to-point link between kuberack (ether1) and stationary (ether2) using `10.254.254.0/30` subnet. This ensures symmetric routing - all inter-LAN traffic flows through both routers.
- **Routing**: Stationary has a static route to `10.10.10.0/24` via `10.254.254.1`; kuberack has a static route to `10.1.1.0/24` via `10.254.254.2`. Internet for each LAN flows out its respective WAN.

### Separated Mode (Fallback Operation)

- **ZeroTier Paths**: High-distance routes over ZeroTier connect `10.10.10.0/24` and `10.1.1.0/24` when the wired interconnect is absent.
- **Independent Gateways**: Each site uses its own WAN; ZeroTier only carries cross-site traffic when separated.

## Provisioning Responsibilities

**Bootstrap script (one-time after reset)**
- Set system identity, build LAN bridge (ports, MAC), enable IPv6 SLAAC/RA on the bridge.
- Optionally add the wired interconnect interface with IPv6 (no IPv4).
- Create interface lists (WAN/LAN/MGMT_ALLOWED), baseline firewall/NAT, WAN DHCP client + IPv6 PD, enable DNS, generate self-signed certs, optionally install ZeroTier binary.
- No IPv4 addresses, no DHCP servers, no static routes—left to Terraform.

**Terraform apply (ongoing)**
- IPv4 addressing: `10.1.1.1/24` on stationary bridge; `10.254.254.2/30` on stationary transit (ether2); `10.254.254.1/30` on kuberack transit (ether1); `10.10.10.1/24` on kuberack bridge.
- DHCP: `stationary-dhcp` for 10.1.1.0/24 with static leases; `kuberack-dhcp` for 10.10.10.0/24 with static leases.
- DNS: resolver settings plus static records/adlists on both routers.
- Routing: static route on stationary to `10.10.10.0/24` via `10.254.254.1`; static route on kuberack to `10.1.1.0/24` via `10.254.254.2`; ZeroTier fallback routes (distance 200) both ways.
- ZeroTier instances/interfaces/addresses and MGMT_ALLOWED membership.
- Users/certs/QoS: mktxp & external_dns users, ACME certs, cake QoS on kuberack WAN, and uploading the bootstrap script.

## VPN

When sites are separated, Zerotier maintains connectivity between the `10.10.10.0/24` and `10.1.1.0/24` networks:

- **VPN Network**: `10.255.255.0/24`
- **RB5009 VPN IP**: `10.255.255.1`
- **RB5009UGS VPN IP**: `10.255.255.2`
- **Purpose**: Site-to-site connectivity, service access, management

## Implementation

The configuration is organized into two Terraform modules:

- **`module.stationary`**: Stationary infrastructure
- **`module.kuberack`**: Kuberack infrastructure

### Usage

- **Normal operation**: `terraform apply`
- **Device specific apply**: `terraform apply -target=module.stationary`

### SSH Access

SSH keys are managed via Terraform from the `ssh_public_keys` field in the secret.

```bash
ssh rb5009    # kuberack RB5009
ssh hex-s     # stationary hEX S

# run commands directly
ssh rb5009 /interface/list/member/print
ssh hex-s /ip/route/print
```

### Bootstrap Scripts

Minimal RouterOS bootstrap scripts handle the initial setup required to prepare a device for Terraform management. The script files (`stationary_rb5009ugs.rsc` and `kuberack_rb5009.rsc`) are generated by Terraform from a single template (`bootstrap.tftpl.rsc`) and are checked into version control.

The final, complex configuration (like VRRP and high-performance routing) is managed by Terraform, which also uploads the latest version of the bootstrap script to the device on every `apply`.

If you modify the template or the configuration variables in `main.tf`, running `terraform apply` will automatically update the script files in `bootstrap/generated/`. You should then review these changes and commit them to version control.

## Bootstrap Process

To bootstrap a new MikroTik device or to update an existing one with the latest script, follow these steps:

1.  **Update Scripts (If Needed)**: If you have changed the bootstrap template or variables, run `terraform apply`. This will update the script files in `bootstrap/generated/`. Review the changes with `git diff` and commit them. For a first-time setup, the necessary scripts are already in the repository.

2.  **Upload Bootstrap Script**: Access the device's UI (WinBox or HTTP) and upload the device-specific bootstrap script (e.g., `stationary_rb5009ugs.rsc` for the RB5009UGS) from the `bootstrap/generated/` directory.

3.  **Reset Configuration**: Navigate to `System -> Reset Configuration` in the UI. Select `No Default Configuration` and choose the script uploaded in Step 2 from the `Run after Reset` option. Confirm and reset the device.

4.  **Initial Access & Configuration**: After the device reboots, it will be accessible by connecting your computer to any of the LAN ports. Your computer will receive an IP address via DHCP in the appropriate range. Access the router at its management IP (`10.1.1.3` for the RB5009UGS).

5.  **Set Admin Password**: Log in with the username `admin` and no password. Immediately set a strong password for the `admin` user. This password should match the credentials defined in your secrets (viewable via `just view`).

6.  **Terraform Management**: The device is now ready for Terraform. Run `terraform apply` again. Terraform will connect via the device's IP and apply the final configuration. It will also upload the latest version of the bootstrap script, so for future updates, you only need to re-run the reset step (Step 3).

## TODO

- [ ] Implement stationary module (RB5009UGS)
  - [x] Minimal bootstrap script
  - [x] Basic network configuration (IP addressing, DHCP)
  - [x] Configure DHCP server with static leases (pannu, JetKVM)
  - [ ] Firewall rules
- [ ] Implement kuberack module (RB5009 + CRS305)
  - [x] RB5009 minimal bootstrap script
  - [x] RB5009 basic network configuration
  - [ ] CRS305 minimal bootstrap script (basic Layer 2 switch)
  - [ ] RB5009 firewall rules
  - [ ] CRS305 basic switch configuration
- [x] DNS and Peer Configuration
  - [x] Set system identity for each router
  - [x] Add authoritative DNS records for all devices (pannu, JetKVM)
- [x] VPN configuration
  - [x] ZeroTier site-to-site tunnel configuration
  - [x] Routing between sites when separated (fallback routes with proper metrics)
  - [x] Management access via ZeroTier tunnel
- [x] Testing and validation
  - [x] Test failover scenarios (~16-17 second convergence time)
  - [x] Performance testing (~50Mbps through ZeroTier tunnel)
- [ ] Refactoring
  - [ ] move DHCP servers to terraform, with initial config being done with static IP configuration
- [ ] CRS310 VLAN-based transit link (future enhancement)
  - [ ] Add CRS310 to Terraform management
  - [ ] Configure VLAN 100 for transit traffic between kuberack and stationary
  - [ ] Set kuberack-facing port as access VLAN 100
  - [ ] Set stationary-facing SFP+ as trunk (VLAN 1 + VLAN 100)
  - [ ] Move transit IP to VLAN interface on stationary (frees ether2 for bridge)
  - [ ] Benefits: No dedicated transit port needed, all router ports available for LAN

## Important Notes

### Device Mode Restrictions

Some MikroTik devices have device-mode security features that may block certain packages like ZeroTier by default. If ZeroTier fails to start, you may need to:

1. **Check if ZeroTier is enabled**:

   ```
   /system device-mode print
   ```

2. **Enable ZeroTier in device mode** (if not already enabled):

   ```
   /system device-mode update zerotier=yes
   ```

3. **Physically press the MODE button** on the device to confirm the change (if applicable)

4. **Reboot the device** for the change to take effect

Without this step, ZeroTier instances may fail to start with device-mode related errors.
