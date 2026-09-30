#!/usr/bin/env bash
# Prints a one-line summary of Claude subscription usage for herdr's tab-row
# status area, from the sidecar that claude-statusline.sh writes. Prints nothing
# when there is no usable data, which makes herdr hide the entry.
#
# Install (needs bash and jq):
#   1. Have Claude Code write the sidecar: point "statusLine" in
#      ~/.claude/settings.json at claude-statusline.sh, or copy its sidecar block
#      (the top of that script) into your own statusline command.
#   2. Add this script to herdr's tab row in ~/.config/herdr/config.toml (append
#      to tab_bar_right if you already have one), then run
#      `herdr server reload-config`:
#        [ui]
#        tab_bar_right = [{ type = "command", command = 'bash "/path/to/claude-usage-status.sh"', interval_seconds = 5, timeout_seconds = 2 }]
usage_file="$HOME/.claude/rate-limit-usage.json"
[ -r "$usage_file" ] || exit 0

jq -r --argjson now "$(date +%s)" '
  def cells(n; c): [range(n)] | map(c) | join("");
  def bar: (. / 100 * 8 | ceil | if . < 0 then 0 elif . > 8 then 8 else . end) as $f
    | cells($f; "█") + cells(8 - $f; "░");
  # Same format as archelon formatReset (src/lib/usage.ts).
  def countdown: (. - $now | floor) as $s
    | if $s <= 0 then "0m" else
        ($s / 86400 | floor) as $d | ($s % 86400 / 3600 | floor) as $h | ($s % 3600 / 60 | floor) as $m
        | if $d > 0 then "\($d)d" + (if $h > 0 then "\($h)h" else "" end)
          elif $h > 0 then "\($h)h" + (if $m > 0 then "\($m)m" else "" end)
          elif $m > 0 then "\($m)m"
          else "<1m" end
      end;
  def segment($name):
    if (type == "object") and (.used_percentage | type) == "number" and (.resets_at | type) == "number"
    then "\($name) \(.used_percentage | bar) \(.used_percentage | round)% \(.resets_at | countdown)"
    else empty end;
  [(.five_hour | segment("5H")), (.seven_day | segment("7D"))]
  | select(length > 0) | join(" · ")
' "$usage_file" 2>/dev/null
exit 0
