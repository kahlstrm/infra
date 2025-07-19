# -----------------------------------------------------------------------------
#               GENERIC MIKROTIK BOOTSTRAP SCRIPT
# -----------------------------------------------------------------------------
# This is a generic bootstrap script for RouterOS devices. Its purpose is to
# configure a device just enough to be managed by Terraform.
#
# All device-specific configuration should be done in the
# 'USER-CONFIGURABLE PARAMETERS' section below.
#
# DO NOT EDIT THE SCRIPT BODY for a single device. If changes are needed,
# they should be reflected across all other router scripts of a similar pattern.
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
:local localBridgePorts {"ether4"; "ether5"}
:local localIpNetwork "10.20.10.0/24"
:local localDhcpPoolStart 100
:local localDhcpPoolEnd 200
:local localDhcpPoolName "local-dhcp"

# --- WAN Configuration ---
:local wanInterface "ether1"

# --- (Optional) Static Peering to Parent Router ---
# To enable, set 'peeringInterface' to a physical port (e.g. "ether2").
:local peeringInterface "ether2"
:local parentLanNetwork "10.10.10.0/24"
:local childIpInLinkNetwork "10.254.254.2/30"
:local parentIpInLinkNetwork "10.254.254.1"
# ------------------------------------------------------------------------------

#-------------------------------------------------------------------------------
#                            DERIVED PARAMETERS
#-------------------------------------------------------------------------------
:local localNetworkPart [:pick $localIpNetwork 0 [:find $localIpNetwork "/"]]
:local localCidrSuffix [:pick $localIpNetwork [:find $localIpNetwork "/"] [:len $localIpNetwork]]
:local localNetworkPrefix [:pick $localNetworkPart 0 ([:len $localNetworkPart] - 1)]
:local localBridgeIpAddress ($localNetworkPrefix . "1")
:local localDhcpPoolRange ($localNetworkPrefix . $localDhcpPoolStart . "-" . $localNetworkPrefix . $localDhcpPoolEnd)
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
:if ([:len $localBridgePorts] > 0) do={
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
  /ip dhcp-server add name=bootstrap address-pool=$localDhcpPoolName interface=$localBridgeName disabled=no;
  /ip dhcp-server network add address=$localIpNetwork gateway=$localBridgeIpAddress dns-server=$localBridgeIpAddress comment="bootstrap";
  /ip address add address="$localBridgeIpAddress$localCidrSuffix" interface=$localBridgeName comment="bootstrap";
  /interface list member add list=LAN interface=$localBridgeName comment="bootstrap";

  # Set the flag to indicate the bridge was created.
  :set isLocalBridgeCreated true;
}

# --- Global Services ---
# Enable DNS and configure a DHCP client on the WAN interface.
/ip dns set allow-remote-requests=yes
/ip dhcp-client add interface=$wanInterface disabled=no comment="bootstrap"

/interface list member add list=WAN interface=$wanInterface comment="bootstrap"
:if ($peeringInterface != "") do={
  /interface list add name=PEERING comment="bootstrap"
  /ip address add address=$childIpInLinkNetwork interface=$peeringInterface comment="bootstrap: static peering"
  /ip route add dst-address=$parentLanNetwork gateway=$parentIpInLinkNetwork comment="bootstrap: static peering"
  /interface list member add list=PEERING interface=$peeringInterface comment="bootstrap"
}
/ip firewall nat add chain=srcnat out-interface-list=WAN ipsec-policy=out,none action=masquerade comment="bootstrap: masquerade"
/ip firewall {
  filter add chain=input action=accept connection-state=established,related,untracked comment="bootstrap: accept established,related,untracked"
  filter add chain=input action=drop connection-state=invalid comment="bootstrap: drop invalid"
  filter add chain=input action=accept protocol=icmp comment="bootstrap: accept ICMP"
  filter add chain=input action=accept dst-address=127.0.0.1 comment="bootstrap: accept to local loopback (for CAPsMAN)"
  :if ($peeringInterface != "") do={
    /ip firewall filter add chain=input action=accept in-interface-list=PEERING comment="bootstrap: accept from parent"
  }
  filter add chain=input action=drop in-interface-list=!LAN comment="bootstrap: drop all not coming from LAN"
  filter add chain=forward action=accept ipsec-policy=in,ipsec comment="bootstrap: accept in ipsec policy"
  filter add chain=forward action=accept ipsec-policy=out,ipsec comment="bootstrap: accept out ipsec policy"
  filter add chain=forward action=accept in-interface-list=PEERING out-interface-list=LAN comment="bootstrap: allow forwarding from peering to LAN"
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
/interface list add name=MGMT_ALLOWED
:if ($isLocalBridgeCreated) do={
  /interface list member add list=MGMT_ALLOWED interface=$localBridgeName
}
:if ($peeringInterface != "") do={
  /interface list member add list=MGMT_ALLOWED interface=$peeringInterface
}
/ip neighbor discovery-settings set discover-interface-list=MGMT_ALLOWED
/tool mac-server set allowed-interface-list=MGMT_ALLOWED
/tool mac-server mac-winbox set allowed-interface-list=MGMT_ALLOWED

:log info bootstrap_script_finished;
:set bootstrapMode;

/certificate
add name=ca common-name=local_ca key-usage=key-cert-sign
add name=self common-name=localhost
sign ca
sign self
/ip service
set www-ssl certificate=self disabled=no
