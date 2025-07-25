# Local Networking

This manages the MikroTik routers that provide redundant connectivity between the portable minirack and stationary infrastructure.

## Network Setup

The network is composed of two main logical networks, connected by a shared high-availability backbone.

- **Minirack LAN**: `10.10.10.0/24` (for devices connected only to the RB5009 and CRS310 switch)
- **Shared LAN (VRRP)**: `10.1.1.0/24` (a high-availability network for critical devices like `pannu` and the U7 Pro AP)
- **VRRP Virtual Gateway**: `10.1.1.1`
- **WireGuard/ZeroTier VPN**: `10.255.255.0/24` (for site-to-site connectivity when separated)

### Network Diagram

```mermaid
graph TB
    subgraph "Shared LAN (10.1.1.0/24)"
        SWITCH[Unmanaged 2.5G Switch]
        U7[U7 Pro AP]
        PANNU[pannu<br/>10.1.1.10]
        SWITCH --> U7
        SWITCH --> PANNU
    end

    subgraph "Minirack (Portable)"
        WAN1[Internet WAN 1]
        RB5009[RB5009<br/>Main Router<br/>Minirack LAN: 10.10.10.1<br/>Shared LAN: 10.1.1.2]
        CRS310[CRS310<br/>Switch]
        RPI5[RPi 5]
        MS01[MS-01]
        ZIMA[Zimaboard 2]

        WAN1 --> RB5009
        RB5009 -- "ether1 (2.5G)" --> SWITCH
        RB5009 -- "10G SFP+" --> CRS310
        CRS310 --> RPI5
        CRS310 --> MS01
        CRS310 --> ZIMA
    end

    subgraph "Stationary"
        WAN2[Internet WAN 2]
        HEXS[hEX S<br/>Failover Router<br/>Shared LAN: 10.1.1.3]
        JETKVM[JetKVM<br/>10.1.1.11]

        WAN2 --> HEXS
        HEXS -- "LAN Bridge" --> SWITCH
        SWITCH --> JETKVM
    end


    RB5009 -.->|VPN<br/>when separated| HEXS

    subgraph "VRRP Virtual Gateway"
        VRRP[10.1.1.1<br/>Shared Virtual IP]
        RB5009 -.->|Priority 255| VRRP
        HEXS -.->|Priority 100| VRRP
    end
```

## How It Works

_Note: The following describes the target architecture for the network. The implementation is ongoing and details are subject to change._

This network is designed for both high performance and automatic failover using a combination of a shared network segment, VRRP, and state-aware DHCP services.

### Connected Mode (Normal High-Performance Operation)

- **Unified Backbone**: A simple unmanaged switch creates a shared Layer 2 network (`10.1.1.0/24`). The RB5009 (via `ether1`) and the hEX S (via a bridge of its LAN ports) connect to this switch. Critical devices like `pannu` and the U7 Pro access point also connect here.
- **Primary Router**: The RB5009 is the primary router (VRRP Master, priority 255) and handles all internet traffic for the shared network.
- **High-Speed Data Path**: `pannu` connects via its 2.5G port to the unmanaged switch, allowing high-speed access to the RB5009 and other devices on the shared network.
- **Central DHCP**: The RB5009 runs the primary DHCP server for the shared network. It provides leases to all devices, including `pannu`.
- **Backup Router (Standby)**: The hEX S is in standby (VRRP Backup, priority 100). Its dedicated DHCP server for the shared network is **disabled** by a VRRP state-change script to prevent conflicts.

### Separated Mode (Failover Operation)

- **Failure Detection**: When the minirack is disconnected or the RB5009 fails, the hEX S detects the loss of VRRP heartbeats and automatically transitions to become the VRRP Master.
- **Failover DHCP Activation**: The moment the hEX S becomes master, a VRRP `on-master` script instantly **enables** its DHCP server.
- **Resilient Connectivity**: This server provides **static DHCP leases** to critical devices (like `pannu` and `JetKVM`), ensuring they can get online or renew their leases even when the main router is unavailable. The gateway remains `10.1.1.1`, which is now controlled by the hEX S.
- **Backup Path**: All traffic from the stationary network now flows through the hEX S and out its own WAN connection.

## VRRP Setup

VRRP handles automatic failover between routers on the shared `10.1.1.0/24` network:

- **Virtual IP**: `10.1.1.1` (gateway for all devices on the shared network)
- **RB5009**: Priority 255 (master when connected)
- **hEX S**: Priority 100 (backup, becomes master when RB5009 unavailable)

## VPN

When sites are separated, WireGuard/Zerotier (TBD) maintains connectivity between the `10.10.10.0/24` and `10.1.1.0/24` networks:

- **VPN Network**: `10.255.255.0/24`
- **RB5009 VPN IP**: `10.255.255.1`
- **hEX S VPN IP**: `10.255.255.2`
- **Purpose**: Site-to-site connectivity, service access, management

## Implementation

The configuration is organized into two Terraform modules:

- **`module.stationary`**: hEX S router and stationary infrastructure
- **`module.minirack`**: RB5009 router and portable minirack devices

### Usage

- **Normal operation**: `terraform apply`
- **Stationary only**: `terraform apply -target=module.stationary`
- **Minirack only**: `terraform apply -target=module.minirack`

### Bootstrap Scripts

Minimal RouterOS bootstrap scripts handle the initial setup required to prepare a device for Terraform management. They configure just enough for the device to be accessible and secure. For now, this includes a basic firewall configuration, which may be fully migrated to Terraform in the future. The final, complex configuration (like VRRP and high-performance routing) is managed by Terraform.

## Bootstrap Process

To bootstrap a new MikroTik device and integrate it into the Terraform-managed network, follow these steps:

1.  **Upload Bootstrap Script**: Access the device's UI (WinBox or HTTP) and upload the device-specific bootstrap script (e.g., `hexS.rsc` for the hEX S) from the `bootstrap/` directory.
2.  **Reset Configuration**: Navigate to `System -> Reset Configuration` in the UI. Select `No Default Configuration` and choose the script uploaded in Step 1 from the `Run after Reset` option. Confirm and reset the device.
3.  **Initial Access & Configuration**: After the device reboots, it will be accessible by connecting your computer to any of the LAN ports (`ether2-5`). Your computer will receive an IP address via DHCP in the `10.1.1.0/24` range. Access the router at `http://10.1.1.3`.
4.  **Set Admin Password**: Log in with the username `admin` and no password. Immediately set a strong password for the `admin` user. This password should match the credentials defined in your secrets (viewable via `just view`).
5.  **Terraform Management**: The device is now ready for Terraform. Terraform will connect via the `10.1.1.3` IP and apply the final configuration, including VRRP, failover DHCP, and DNS records.

## TODO

- [ ] Implement stationary module (hEX S)
  - [x] Minimal bootstrap script
  - [x] Basic network configuration (IP addressing, DHCP)
  - [x] Configure failover DHCP server with static leases (pannu, JetKVM)
  - [x] VRRP setup for failover
  - [ ] Firewall rules
- [ ] Implement minirack module (RB5009 + CRS310)
  - [ ] RB5009 minimal bootstrap script
  - [ ] CRS310 minimal bootstrap script (basic Layer 2 switch)
  - [ ] RB5009 basic network configuration
  - [ ] RB5009 VRRP setup (master role)
  - [ ] RB5009 firewall rules
  - [ ] CRS310 basic switch configuration
- [ ] DNS and Peer Configuration
  - [ ] Set system identity for each router
  - [ ] Configure peer DNS resolution between routers
  - [ ] Add authoritative DNS records for all devices (routers, pannu, JetKVM)
- [ ] VPN configuration
  - [ ] Choose between WireGuard and ZeroTier
  - [ ] Site-to-site tunnel configuration
  - [ ] Routing between sites when separated
- [ ] Testing and validation
  - [ ] Test failover scenarios
  - [ ] Test lift and shift functionality
  - [ ] Performance testing