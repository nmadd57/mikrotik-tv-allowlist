# setup.rsc — one-time install of the TV domain allowlist sync mechanism.
# Run this once (paste into a RouterOS terminal, or import as a script and
# run it). It does NOT touch your firewall filter rules — see README.md for
# the firewall wiring, which depends on your existing rule layout.
#
# CUSTOMIZE before running:
:local rawBase "https://raw.githubusercontent.com/nmadd57/mikrotik-tv-allowlist/main"
:local syncScriptUrl ($rawBase . "/scripts/sync-tv-domains.rsc")
:local scriptName "sync-tv-domains"
:local schedulerInterval "6h"
:local minDnsCacheKiB 8192

# 1) Make sure the DNS cache is big enough. A full cache silently drops new
#    entries (logged as "dns,error cache full, not storing"), which breaks
#    the regexp -> address-list population this whole mechanism depends on.
:if ([/ip dns get cache-size] < $minDnsCacheKiB) do={
  /ip dns set cache-size=$minDnsCacheKiB
  /ip dns cache flush
  :log info ("setup: raised DNS cache-size to " . $minDnsCacheKiB . "KiB")
}

# 2) Fetch the sync script itself from the repo and install/update it as a
#    RouterOS system script.
/tool fetch url=$syncScriptUrl dst-path="sync-tv-domains-install.rsc" output=file check-certificate=yes
:delay 1s
:local syncSource [/file get "sync-tv-domains-install.rsc" contents]
/file remove "sync-tv-domains-install.rsc"

:if ([:len [/system script find name=$scriptName]] > 0) do={
  /system script set [find name=$scriptName] source=$syncSource policy=read,write,test,ftp
} else={
  /system script add name=$scriptName source=$syncSource policy=read,write,test,ftp
}
:log info "setup: installed/updated sync-tv-domains script"

# 3) Run it once immediately so the address-list is populated right away.
/system script run $scriptName

# 4) Schedule it to keep refreshing.
:if ([:len [/system scheduler find name=$scriptName]] = 0) do={
  /system scheduler add name=$scriptName interval=$schedulerInterval on-event=("/system script run " . $scriptName) comment="Refresh TV streaming domain allowlist from repo"
  :log info ("setup: scheduled " . $scriptName . " every " . $schedulerInterval)
}

:log info "setup: done. Now wire up the firewall rules manually - see README.md."
