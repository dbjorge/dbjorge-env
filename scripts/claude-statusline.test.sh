#!/usr/bin/env bash
# Verifies the statusline script tees rate_limits to the sidecar cache.
set -euo pipefail
script="$(cd "$(dirname "$0")" && pwd)/claude-statusline.sh"

fail() { echo "FAIL: $1" >&2; exit 1; }

# Case 1: rate_limits present -> sidecar written with flattened shape.
home1="$(mktemp -d "${TMPDIR:-/tmp}/statusline-test.XXXXXX")"; mkdir -p "$home1/.claude"
sample='{"model":{"display_name":"Opus"},"cwd":"/x","context_window":{"context_window_size":200000,"current_usage":{"input_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}},"rate_limits":{"five_hour":{"used_percentage":42,"resets_at":1782170000},"seven_day":{"used_percentage":68,"resets_at":1782400000}}}'
HOME="$home1" bash "$script" <<<"$sample" >/dev/null
f="$home1/.claude/rate-limit-usage.json"
[ -f "$f" ] || fail "sidecar not written when rate_limits present"
jq -e '.five_hour.used_percentage==42 and .five_hour.resets_at==1782170000 and .seven_day.used_percentage==68 and .seven_day.resets_at==1782400000 and (.captured_at|type)=="number"' "$f" >/dev/null \
  || fail "sidecar contents wrong: $(cat "$f")"

# Case 2: no rate_limits -> no sidecar file created.
home2="$(mktemp -d "${TMPDIR:-/tmp}/statusline-test.XXXXXX")"; mkdir -p "$home2/.claude"
HOME="$home2" bash "$script" <<<'{"model":{"display_name":"Opus"},"cwd":"/x"}' >/dev/null
[ -f "$home2/.claude/rate-limit-usage.json" ] && fail "sidecar written when rate_limits absent" || true

# Case 3: effort.level present -> appended to model name.
home3="$(mktemp -d "${TMPDIR:-/tmp}/statusline-test.XXXXXX")"; mkdir -p "$home3/.claude"
out=$(HOME="$home3" bash "$script" <<<'{"model":{"display_name":"Opus 5.5 (1M context)"},"cwd":"/x","effort":{"level":"medium"}}')
[ "$out" = "/x  Opus 5.5 medium" ] || fail "effort not shown: '$out'"

# Case 4: effort absent -> model name only.
out=$(HOME="$home3" bash "$script" <<<'{"model":{"display_name":"Opus 5.5"},"cwd":"/x"}')
[ "$out" = "/x  Opus 5.5" ] || fail "unexpected output without effort: '$out'"

echo "PASS"
