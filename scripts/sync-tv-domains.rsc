# sync-tv-domains — pulls per-app domain allowlists from a GitHub repo and
# rebuilds /ip/dns/static regexp entries feeding a shared firewall
# address-list. See ../README.md for the matching firewall setup.
#
# CUSTOMIZE these two values for your setup, then install via setup.rsc
# (or paste this whole script into /system script, run once, and schedule).

:local addressList "tv-streaming-allowed"
:local rawBase "https://raw.githubusercontent.com/nmadd57/mikrotik-tv-allowlist/main/domains"

# Add/remove entries here to match which domains/*.txt files you want synced.
:local apps {"netflix"; "disneyplus"; "youtube"; "samsung-update"}
# roku-update intentionally not included by default — see domains/roku-update.txt

:foreach app in=$apps do={
  :local url ($rawBase . "/" . $app . ".txt")
  :local fname ("gist-" . $app . ".txt")

  :do {
    /tool fetch url=$url dst-path=$fname output=file check-certificate=yes
    :delay 1s

    :local content [/file get $fname contents]
    /file remove $fname

    # remove this app's previously-synced entries only
    /ip dns static remove [find where comment~("^gist-sync:" . $app . ":")]

    # split content into lines
    :local lines {""}
    :local buf ""
    :local i 0
    :while ($i < [:len $content]) do={
      :local ch [:pick $content $i ($i + 1)]
      :if ($ch = "\n") do={
        :set lines ($lines , $buf)
        :set buf ""
      } else={
        :if ($ch != "\r") do={ :set buf ($buf . $ch) }
      }
      :set i ($i + 1)
    }
    :if ([:len $buf] > 0) do={ :set lines ($lines , $buf) }

    :foreach line in=$lines do={
      :if ([:len $line] > 0 && [:pick $line 0 1] != "#") do={
        :local dom $line
        :local label "gist"
        :local sep [:find $line "|"]
        :if ($sep != nil) do={
          :set dom [:pick $line 0 $sep]
          :set label [:pick $line ($sep + 1) [:len $line]]
        }

        # escape literal dots for regex use
        :local escDom ""
        :local j 0
        :while ($j < [:len $dom]) do={
          :local c [:pick $dom $j ($j + 1)]
          :if ($c = ".") do={ :set escDom ($escDom . "\\.") } else={ :set escDom ($escDom . $c) }
          :set j ($j + 1)
        }
        :local rx ("^(.*\\.)?" . $escDom . "\$")

        /ip dns static add regexp=$rx type=FWD address-list=$addressList comment=("gist-sync:" . $app . ":" . $label)
      }
    }
    :log info ("sync-tv-domains: refreshed " . $app . " from repo")
  } on-error={
    :log warning ("sync-tv-domains: fetch/parse failed for " . $app . ", leaving its existing entries in place")
  }
}
