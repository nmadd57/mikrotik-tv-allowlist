# MikroTik TV domain allowlist

Lets specific devices on a restricted VLAN (e.g. an IoT/guest network with no
general internet access) reach a curated set of streaming/update domains,
without opening full outbound access.

How it works: RouterOS's `/ip/dns/static` supports `regexp` + `address-list`
entries — when a client's DNS query (routed through the router itself)
matches the regex, the *real* resolved IP gets added to the named firewall
address-list automatically, expiring on the DNS answer's TTL. A firewall
rule then only accepts traffic to that address-list. This repo keeps the
domain lists as plain text files and a script that rebuilds those DNS
entries from them, so updating the allowlist is a git commit instead of a
router login.

## Repo layout

- `domains/*.txt` — one file per app/service. Format: `domain|label` per
  line, one entry per line, `#` for comments. Subdomains are matched
  automatically (`netflix.com` also matches `www.netflix.com`, etc).
- `scripts/sync-tv-domains.rsc` — fetches each `domains/*.txt` file over
  HTTPS and rebuilds the DNS regexp entries feeding a shared address-list.
- `scripts/setup.rsc` — one-time install: bumps DNS cache size if needed,
  installs the sync script on the router, runs it once, schedules it.
- `scripts/setup-firewall.rsc` — creates the device/domain address-lists
  and the accept rule. Does not position the rule for you (see below).

## Install

1. Fork/copy this repo (or just point at raw URLs from your own copy).
2. Edit `scripts/sync-tv-domains.rsc` and `scripts/setup.rsc`: replace
   `<OWNER>/<REPO>` with your repo's path.
3. On the router, paste `scripts/setup.rsc` into a terminal (or import and
   run it as a script). This installs and schedules the sync job and
   populates the address-list.
4. Edit `scripts/setup-firewall.rsc`: set `deviceList`/`domainList` names,
   your `wanInterfaceList` (check `/interface/list/print` — often `WAN`),
   and the device IP(s) to cover. Run it.
5. **Manually reorder the new firewall rule.** `setup-firewall.rsc` adds the
   accept rule at the end of the filter chain, which is after any existing
   "no internet" drop rule for that VLAN — it won't do anything until moved
   above it:
   ```
   /ip firewall filter print where chain=forward
   /ip firewall filter move [find comment="TV streaming domains allowed outbound"] destination=<id-of-your-block-rule>
   ```
   Worked example (Itokawa): the IoT VLAN's outbound block was rule `*25`
   (`IoT: no internet`, `drop out-interface-list=WAN`); the new accept rule
   was moved to sit immediately before it.
6. If you want a device to also reach something internal (e.g. a Plex
   server) without going through the domain allowlist at all, add a
   separate accept rule matching `dst-address=<internal IP>` with no
   `out-interface-list`, placed before whatever rule blocks that VLAN from
   reaching the rest of your network.

## Adding/removing a domain

Edit the relevant `domains/*.txt` file and push. On the router, either wait
for the next scheduled run or force it immediately:
```
/system script run sync-tv-domains
```

## Notes / gotchas found while building this

- `/file get` needs the filename passed directly
  (`/file get $fname contents`), not via `[find name=$fname]` — the latter
  fails with a "bad parameter name" syntax error.
- A full DNS cache (`/ip/dns print` → `cache-used` = `cache-size`) silently
  drops new entries (`dns,error cache full, not storing` in the log) and
  breaks this whole mechanism. `setup.rsc` checks and raises it if needed.
- Two DNS static entries can't share the same `regexp` — if you're
  migrating from a manually-built allowlist to this repo, remove the old
  entries first or the sync script's `/ip dns static add` calls will fail
  with "entry already exists".
- Editing a `PATCH` to a RouterOS script's `source` via the REST API can
  silently reset its `policy` field to empty if you don't include it in the
  same request — which then makes `/tool fetch` (and anything else the
  script does) fail with no obvious error, since it just falls into the
  script's own `on-error` handler. Always send `policy` alongside `source`.
- No official Roku domain list exists for update-vs-telemetry traffic;
  community blocklists disagree even on individual hostnames
  (`cloudservices.roku.com` is protected by one list and blocked by
  another). `domains/roku-update.txt` is included but intentionally not
  wired into the default `apps` list in `sync-tv-domains.rsc` — recommended
  approach is to packet-capture a real device's firmware-check traffic once
  one is in scope, rather than guess.
