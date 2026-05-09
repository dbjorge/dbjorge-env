#!/usr/bin/env bash
#
# Dismiss GitHub notifications that are from dependabot and don't @mention you.
#
# Uses title-based heuristics to detect dependabot PRs (dependabot doesn't
# appear in the notification payload, but its titles are very predictable).
#
# Pass --dry-run to preview what would be dismissed without taking action.

set -euo pipefail

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
fi

# Fetch all notifications as JSON, handling paginated output (gh may emit
# multiple JSON arrays when paginating).
raw="$(gh api notifications --paginate)"

# Use jq to filter and extract the notifications we want to dismiss:
#   - title matches dependabot patterns
#   - reason is NOT "mention"
candidates="$(echo "$raw" | jq -s '
  [.[][] |
    select(
      (.subject.title |
        test("^(chore|build|chore\\(deps\\)|build\\(deps\\)|build\\(deps-dev\\)): bump "; "i")
      ) and
      (.reason != "mention")
    ) |
    { id, reason, repo: .repository.full_name, title: .subject.title }
  ]
')"

count="$(echo "$candidates" | jq 'length')"

if [[ "$count" -eq 0 ]]; then
  echo "No dependabot notifications to dismiss."
  exit 0
fi

echo "Found $count dependabot notification(s) to dismiss:"
echo "$candidates" | jq -r '.[] | "  \(.repo) - \(.title) (reason: \(.reason))"'
echo

if [[ "$DRY_RUN" == true ]]; then
  echo "[dry-run] Would dismiss $count notification(s). Pass without --dry-run to execute."
  exit 0
fi

dismissed=0
failed=0
echo "$candidates" | jq -r '.[].id' | while read -r thread_id; do
  if gh api -X DELETE "notifications/threads/$thread_id" --silent 2>/dev/null; then
    dismissed=$((dismissed + 1))
  else
    echo "  Failed to dismiss thread $thread_id" >&2
    failed=$((failed + 1))
  fi
done

echo "Done. Dismissed $count notification(s)."
