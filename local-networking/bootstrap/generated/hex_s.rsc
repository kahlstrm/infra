# -----------------------------------------------------------------------------
#               GENERIC MIKROTIK BOOTSTRAP SCRIPT TEMPLATE
# -----------------------------------------------------------------------------
# This is a generic bootstrap script for RouterOS devices. Its purpose is to
# configure a device just enough to be managed by Terraform.
# -----------------------------------------------------------------------------

:global bootstrapMode;
:global isLocalBridgeCreated false;
:log info "Starting bootstrap script";

# ------------------------------------------------------------------------------
#                          USER-CONFIGURABLE PARAMETERS
# ------------------------------------------------------------------------------
# --- System Identity ---
:local systemIdentity "hex-s"

# --- Local LAN Configuration ---
:local localBridgeName "local-bridge"
:local localBridgePorts {"ether2"; "ether3"; "ether4"; "ether5"}
:local localIpNetwork "10.1.1.0/24"
:local localBridgeIpAddress "10.1.1.1"
# optional, leave empty if don't want secondary bridge IP
:local secondaryLocalBridgeIpAddress "10.1.1.3"
:local localDhcpServerName "vrrp-dhcp"
:local localDhcpPoolStart 100
:local localDhcpPoolEnd 254
:local localDhcpPoolName "vrrp-dhcp"
:local localDhcpServerLeaseTime 1m

# --- Shared LAN Configuration ---
# This is a dedicated interface for the shared VRRP network.
# Optional set sharedLanInterface empty to disable
:local sharedLanInterface ""
:local sharedLanIpAddressNetwork ""

# --- WAN Configuration ---
:local wanInterface "ether1"
# ------------------------------------------------------------------------------

#-------------------------------------------------------------------------------
#                            DERIVED PARAMETERS
#-------------------------------------------------------------------------------
:local localNetworkPart [:pick $localIpNetwork 0 [:find $localIpNetwork "/"]]
:local localCidrSuffix [:pick $localIpNetwork [:find $localIpNetwork "/"] [:len $localIpNetwork]]
:local localNetworkPrefix [:pick $localNetworkPart 0 ([:len $localNetworkPart] - 1)]
:local localDhcpPoolRange ($localNetworkPrefix . $localDhcpPoolStart . "-" . $localNetworkPrefix . $localDhcpPoolEnd)
:local createLocalBridge ([:len $localBridgePorts] > 0)
#-------------------------------------------------------------------------------

#-------------------------------------------------------------------------------
# Apply configuration.
# these commands are executed after installation or configuration reset
#-------------------------------------------------------------------------------
/system identity set name=$systemIdentity

# wait for interfaces
:local count 0;
:while ([/interface ethernet find] = "") do={
  :if ($count = 30) do={
    :log warning "bootstrap: Unable to find ethernet interfaces";
    /quit;
  }
  :delay 1s; :set count ($count +1);
};
/interface list add name=WAN comment="bootstrap"
/interface list add name=LAN comment="bootstrap"
# --- Local Bridge Setup ---
# Create a bridge and DHCP server only if there are interfaces defined.
:if ($createLocalBridge) do={
  /interface bridge
    add name=$localBridgeName disabled=no protocol-mode=rstp comment="bootstrap";

  # Assign a stable MAC address from the first port in the list.
  :local firstPort [:pick $localBridgePorts 0];
  /interface bridge set $localBridgeName admin-mac=[/interface ethernet get $firstPort mac-address] auto-mac=no;

  # Add only the specified interfaces to the bridge.
  :foreach port in=$localBridgePorts do={
    /interface bridge port add bridge=$localBridgeName interface=$port comment=bootstrap;
  }

  # Configure IP, DHCP, and add to LAN interface list.
  /ip pool add name=$localDhcpPoolName ranges=$localDhcpPoolRange;
  /ip dhcp-server add name=$localDhcpServerName address-pool=$localDhcpPoolName interface=$localBridgeName lease-time=$localDhcpServerLeaseTime use-reconfigure=yes disabled=no comment="bootstrap";
  /ip dhcp-server network add address=$localIpNetwork gateway=$localBridgeIpAddress dns-server=$localBridgeIpAddress comment="bootstrap";
  /ip address add address="$localBridgeIpAddress$localCidrSuffix" interface=$localBridgeName comment="bootstrap";
  :if ($secondaryLocalBridgeIpAddress != "") do={
    /ip address add address="$secondaryLocalBridgeIpAddress$localCidrSuffix" interface=$localBridgeName comment="bootstrap";
  }
  /interface list member add list=LAN interface=$localBridgeName comment="bootstrap";

  # Set the flag to indicate the bridge was created.
  :set isLocalBridgeCreated true;
}

# --- Shared LAN Setup ---
:if ($sharedLanInterface != "") do={
  /ip address add address="$sharedLanIpAddressNetwork" interface=$sharedLanInterface comment="bootstrap: shared LAN for VRRP";
  /interface list member add list=LAN interface=$sharedLanInterface comment="bootstrap";
}

# --- Global Services ---
# Enable DNS and configure a DHCP client on the WAN interface.
/ip dns set allow-remote-requests=yes
/ip dhcp-client add interface=$wanInterface disabled=no comment="bootstrap"

/interface list member add list=WAN interface=$wanInterface comment="bootstrap"
/ip firewall nat add chain=srcnat out-interface-list=WAN ipsec-policy=out,none action=masquerade comment="bootstrap: masquerade"
/ip firewall {
  filter add chain=input action=accept connection-state=established,related,untracked comment="bootstrap: accept established,related,untracked"
  filter add chain=input action=drop connection-state=invalid comment="bootstrap: drop invalid"
  filter add chain=input action=accept protocol=icmp comment="bootstrap: accept ICMP"
  filter add chain=input action=accept dst-address=127.0.0.1 comment="bootstrap: accept to local loopback (for CAPsMAN)"
  filter add chain=input action=drop in-interface-list=!LAN comment="bootstrap: drop all not coming from LAN"
  filter add chain=forward action=accept ipsec-policy=in,ipsec comment="bootstrap: accept in ipsec policy"
  filter add chain=forward action=accept ipsec-policy=out,ipsec comment="bootstrap: accept out ipsec policy"
  filter add chain=forward action=fasttrack-connection connection-state=established,related comment="bootstrap: fasttrack"
  filter add chain=forward action=accept connection-state=established,related,untracked comment="bootstrap: accept established,related, untracked"
  filter add chain=forward action=drop connection-state=invalid comment="bootstrap: drop invalid"
  filter add chain=forward action=drop connection-state=new connection-nat-state=!dstnat in-interface-list=WAN comment="bootstrap: drop all from WAN not DSTNATed"
}
/ipv6 firewall {
  address-list add list=bad_ipv6 address=::/128 comment="bootstrap: unspecified address"
  address-list add list=bad_ipv6 address=::1 comment="bootstrap: lo"
  address-list add list=bad_ipv6 address=fec0::/10 comment="bootstrap: site-local"
  address-list add list=bad_ipv6 address=::ffff:0:0/96 comment="bootstrap: ipv4-mapped"
  address-list add list=bad_ipv6 address=::/96 comment="bootstrap: ipv4 compat"
  address-list add list=bad_ipv6 address=100::/64 comment="bootstrap: discard only "
  address-list add list=bad_ipv6 address=2001:db8::/32 comment="bootstrap: documentation"
  address-list add list=bad_ipv6 address=2001:10::/28 comment="bootstrap: ORCHID"
  address-list add list=bad_ipv6 address=3ffe::/16 comment="bootstrap: 6bone"
  filter add chain=input action=accept connection-state=established,related,untracked comment="bootstrap: accept established,related,untracked"
  filter add chain=input action=drop connection-state=invalid comment="bootstrap: drop invalid"
  filter add chain=input action=accept protocol=icmpv6 comment="bootstrap: accept ICMPv6"
  filter add chain=input action=accept protocol=udp dst-port=33434-33534 comment="bootstrap: accept UDP traceroute"
  filter add chain=input action=accept protocol=udp dst-port=546 src-address=fe80::/10 comment="bootstrap: accept DHCPv6-Client prefix delegation."
  filter add chain=input action=accept protocol=udp dst-port=500,4500 comment="bootstrap: accept IKE"
  filter add chain=input action=accept protocol=ipsec-ah comment="bootstrap: accept ipsec AH"
  filter add chain=input action=accept protocol=ipsec-esp comment="bootstrap: accept ipsec ESP"
  filter add chain=input action=accept ipsec-policy=in,ipsec comment="bootstrap: accept all that matches ipsec policy"
  filter add chain=input action=drop in-interface-list=!LAN comment="bootstrap: drop everything else not coming from LAN"
  filter add chain=forward action=fasttrack-connection connection-state=established,related comment="bootstrap: fasttrack6"
  filter add chain=forward action=accept connection-state=established,related,untracked comment="bootstrap: accept established,related,untracked"
  filter add chain=forward action=drop connection-state=invalid comment="bootstrap: drop invalid"
  filter add chain=forward action=drop src-address-list=bad_ipv6 comment="bootstrap: drop packets with bad src ipv6"
  filter add chain=forward action=drop dst-address-list=bad_ipv6 comment="bootstrap: drop packets with bad dst ipv6"
  filter add chain=forward action=drop protocol=icmpv6 hop-limit=equal:1 comment="bootstrap: rfc4890 drop hop-limit=1"
  filter add chain=forward action=accept protocol=icmpv6 comment="bootstrap: accept ICMPv6"
  filter add chain=forward action=accept protocol=139 comment="bootstrap: accept HIP"
  filter add chain=forward action=accept protocol=udp dst-port=500,4500 comment="bootstrap: accept IKE"
  filter add chain=forward action=accept protocol=ipsec-ah comment="bootstrap: accept ipsec AH"
  filter add chain=forward action=accept protocol=ipsec-esp comment="bootstrap: accept ipsec ESP"
  filter add chain=forward action=accept ipsec-policy=in,ipsec comment="bootstrap: accept all that matches ipsec policy"
  filter add chain=forward action=drop in-interface-list=!LAN comment="bootstrap: drop everything else not coming from LAN"
}
# --- System Services ---
# Allow management access only from trusted interfaces.
/interface list add name=MGMT_ALLOWED comment="bootstrap"
:if ($createLocalBridge) do={
  /interface list member add list=MGMT_ALLOWED interface=$localBridgeName comment="bootstrap"
}
:if ($sharedLanInterface != "") do={
  /interface list member add list=MGMT_ALLOWED interface=$sharedLanInterface comment="bootstrap"
}
/ip neighbor discovery-settings set discover-interface-list=MGMT_ALLOWED
/tool mac-server set allowed-interface-list=MGMT_ALLOWED
/tool mac-server mac-winbox set allowed-interface-list=MGMT_ALLOWED

:log info bootstrap_script_finished;
:set bootstrapMode;

/certificate {
  add name=ca common-name=local_ca key-usage=key-cert-sign
  add name=self common-name=localhost
  sign ca
  sign self
}

# there seems to be some race-condition with certificate signing and the ip service www-ssl enabling
# where the ip service doesn't always find the signed cert
# so let's make while loop to wait for 5s to find the certifcation
:local ms 0
:local timeout 5000
:while ([:len [/certificate find name="self"]] = 0 && $ms < $timeout) do={
    :delay 500ms
    :set ms ($ms + 500)
}
:if ([:len [/certificate find name="self"]] = 0) do={
    :log error ("Timeout waiting for certificate 'self' after " . $ms . " ms")
    :error "Timeout waiting for certificate 'self'"
}
:log info ("Found certificate 'self' after " . $ms . " ms")
/ip service set www-ssl certificate=self disabled=no
