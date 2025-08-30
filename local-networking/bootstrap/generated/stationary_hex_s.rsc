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
:local systemIdentity "stationary-hex-s"

# --- Local LAN Configuration ---
:local localBridgeName "local-bridge"
:local localBridgePorts {"ether2"; "ether3"; "ether4"; "ether5"}
:local localIpv6Address "fd00:de:ad:1::3/64"

# --- Shared LAN Configuration ---
# This is a dedicated interface for the shared VRRP network.
# Optional set sharedLanInterface empty to disable
:local sharedLanInterface ""
:local sharedLanIpv6AddressNetwork ""

# --- WAN Configuration ---
:local wanInterface "ether1"
# ------------------------------------------------------------------------------

#-------------------------------------------------------------------------------
#                            DERIVED PARAMETERS
#-------------------------------------------------------------------------------
:local createLocalBridge ([:len $localBridgePorts] > 0)
:local localIpv6Host [:pick $localIpv6Address 0 [:find $localIpv6Address "/"]]
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
# Create a bridge for the local LAN.
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

  # --- IP Setup for Local LAN ---
  /ipv6 address add address=$localIpv6Address interface=$localBridgeName advertise=yes comment="bootstrap";
  /ipv6 nd prefix default set autonomous=yes;
  /ipv6 nd disable [find default]
  /ipv6 nd add interface=$localBridgeName advertise-dns=yes dns=$localIpv6Host managed-address-configuration=no other-configuration=no

  /interface list member add list=LAN interface=$localBridgeName comment="bootstrap";

  # Set the flag to indicate the bridge was created.
  :set isLocalBridgeCreated true;
}

# --- Static DNS Records for All Routers ---
# Add records for all managed routers to solve provider DNS resolution.
/ip dns static add name="kuberack-rb5009.networking.kalski.xyz" address=fd00:de:ad:10::1 type=AAAA comment="bootstrap"
/ip dns static add name="stationary-hex-s.networking.kalski.xyz" address=fd00:de:ad:1::3 type=AAAA comment="bootstrap"

# --- Shared LAN Setup ---
:if ($sharedLanInterface != "") do={
  /ipv6 address add address="$sharedLanIpv6AddressNetwork" interface=$sharedLanInterface comment="bootstrap: shared LAN for VRRP";
  /interface list member add list=LAN interface=$sharedLanInterface comment="bootstrap";
}

# --- Management Routes ---
# Routes to reach other routers' management networks during bootstrap
/ipv6 route add dst-address=fd00:de:ad:10::/64 gateway=fd00:de:ad:1::2 distance=255 comment="bootstrap: route to RB5009 kuberack for management"
#
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

# --- Global Services ---
# Enable DNS and configure DHCP clients on the WAN for dual-stack connectivity.
/ip dns set allow-remote-requests=yes
/ip dhcp-client add interface=$wanInterface disabled=no comment="bootstrap"
/ipv6 settings set accept-router-advertisements=yes forward=yes
/ipv6 dhcp-client add interface=$wanInterface request=prefix pool-name=wan-ipv6-pool disabled=no comment="bootstrap"
/ipv6 nd add interface=$wanInterface advertise-dns=no advertise-mac-address=no
/ipv6 address add from-pool=wan-ipv6-pool interface=$localBridgeName advertise=yes comment="bootstrap"

/interface list member add list=WAN interface=$wanInterface comment="bootstrap"
/ip firewall nat add chain=srcnat out-interface-list=WAN ipsec-policy=out,none action=masquerade comment="bootstrap: masquerade"
/ip firewall {
  filter add chain=input action=accept connection-state=established,related,untracked comment="bootstrap: accept established,related,untracked"
  filter add chain=input action=drop connection-state=invalid comment="bootstrap: drop invalid"
  filter add chain=input action=accept protocol=icmp comment="bootstrap: accept ICMP"
  filter add chain=input action=accept dst-address=127.0.0.1 comment="bootstrap: accept to local loopback (for CAPsMAN)"
  filter add chain=input action=accept in-interface-list=MGMT_ALLOWED comment="bootstrap: allow incoming from MGMT_ALLOWED"
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
  filter add chain=input action=accept in-interface-list=MGMT_ALLOWED comment="bootstrap: allow incoming from MGMT_ALLOWED"
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

# --- ZeroTier Installation ---
# Check if the ZeroTier package is installed and enabled. If not, find and install it.
# The device will reboot automatically to apply the changes.
:if ([/system package print count-only where name="zerotier" and disabled=no] > 0) do={
  :log info "ZeroTier package is already installed and enabled.";
} else={
  :log info "ZeroTier package not found or is disabled; attempting to install.";
  /system package update check-for-updates;
  :delay 5s;
  :if ([/system package print count-only where name="zerotier"] > 0) do={
      :log info "Found ZeroTier package, enabling it now.";
      /system package enable zerotier;
      :log info "Rebooting to apply package changes.";
      :execute script="/system package apply-changes"
  } else={
      :log warning "Could not find ZeroTier package after checking for updates.";
  }
}
# reboot for ipv6 accept-router-advertisement setting to be enabled
:log info "Rebooting for ipv6 accept-router-advertisement change"
:execute script="/system reboot"
