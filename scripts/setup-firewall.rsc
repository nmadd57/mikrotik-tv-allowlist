# setup-firewall.rsc — creates the address-lists and the two accept rules
# this policy needs. Does NOT position them for you: firewall rule order is
# specific to your existing config, so after running this, use
# `/ip firewall filter print` and `/ip firewall filter move` to place the
# new rules BEFORE whatever rule currently blocks this VLAN's outbound
# traffic. See README.md for a worked example.
#
# CUSTOMIZE before running:
:local deviceList "vlan99-internet-allowed"
:local domainList "tv-streaming-allowed"
:local wanInterfaceList "WAN"
# One entry per device you want covered by this policy. Add more lines as needed.
:local deviceIPs {"192.168.99.5"}

:foreach ip in=$deviceIPs do={
  :if ([:len [/ip firewall address-list find list=$deviceList address=$ip]] = 0) do={
    /ip firewall address-list add list=$deviceList address=$ip
  }
}

:if ([:len [/ip firewall filter find where chain="forward" src-address-list=$deviceList dst-address-list=$domainList]] = 0) do={
  /ip firewall filter add chain=forward action=accept src-address-list=$deviceList dst-address-list=$domainList out-interface-list=$wanInterfaceList comment="TV streaming domains allowed outbound"
  :log warning "setup-firewall: rule added at the END of the filter chain - move it before your VLAN's outbound-block rule now"
}
