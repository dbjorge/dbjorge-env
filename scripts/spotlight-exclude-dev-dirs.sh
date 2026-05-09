#!/usr/bin/env bash
#
# spotlight-exclude-dev-dirs.sh
#
# Drops .metadata_never_index marker files in high-churn dev directories so
# Spotlight stops indexing them. Idempotent — safe to re-run.
#
# Why this matters:
#   Spotlight indexes every file it sees, including node_modules, .git
#   internals, build outputs, and Docker/Parallels VM data. On a dev machine
#   these directories churn constantly, and Spotlight's index can grow to
#   hundreds of GB without any user-visible files (it lives in
#   /private/var/db/Spotlight-V100, which is SIP-protected and invisible to
#   `du` even with sudo + Full Disk Access). Symptoms: "System Data" balloons
#   in Storage settings; df-used >> sum of `du` totals.
#
# This script uses Apple's documented .metadata_never_index marker, which
# Spotlight respects when traversing a directory tree.
#
# After running, prune existing index bloat with:
#   sudo mdutil -E /
# That triggers a full reindex from clean state. It takes hours of background
# CPU/IO, but the new index respects the markers and stays small.
#
# Usage:
#   ./spotlight-exclude-dev-dirs.sh

set -euo pipefail

DIRS=(
  "$HOME/repos"
  "$HOME/worktrees"
  "$HOME/.npm"
  "$HOME/.cache"
  "$HOME/.yarn"
  "$HOME/Library/Caches"
  "$HOME/Library/pnpm"
  "$HOME/.local/share/pnpm"
  "$HOME/Library/Containers/com.docker.docker"
  "$HOME/tmp"
  "/tmp"
)

added=0
existed=0
skipped=0

for d in "${DIRS[@]}"; do
  if [ -d "$d" ]; then
    marker="$d/.metadata_never_index"
    if [ -f "$marker" ]; then
      printf "  already marked  %s\n" "$d"
      existed=$((existed + 1))
    else
      touch "$marker"
      printf "  marked          %s\n" "$d"
      added=$((added + 1))
    fi
  else
    printf "  not present     %s\n" "$d"
    skipped=$((skipped + 1))
  fi
done

echo ""
echo "Summary: $added newly marked, $existed already marked, $skipped not present."

if [ "$added" -gt 0 ]; then
  echo ""
  echo "To prune the existing index bloat (one-time, takes hours of background work):"
  echo "  sudo mdutil -E /"
fi
