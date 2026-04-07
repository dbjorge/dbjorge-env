#!/usr/bin/env bash
#
# cleanup-disk.sh
#
# Frees disk space by cleaning up browser caches (Puppeteer, Playwright,
# Selenium) and stale node_modules directories.
#
# Usage:
#   cleanup-disk.sh [--dry-run] [--only=TYPE]
#
# Options:
#   --dry-run     Show what would be deleted without actually deleting anything
#   --only=TYPE   Only run one type of cleanup: "browser_caches" or "node_modules"
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DRY_RUN=false
ONLY=""

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --only=browser_caches|--only=node_modules) ONLY="${arg#--only=}" ;;
    --only=*) echo "Unknown type: ${arg#--only=} (expected 'browser_caches' or 'node_modules')"; exit 1 ;;
    *) echo "Usage: $0 [--dry-run] [--only=TYPE]"; exit 1 ;;
  esac
done

cache_dirs_to_delete=()
total_cache_size=0

check_cache_dir() {
  local label="$1"
  local dir="$2"

  if [ ! -d "$dir" ]; then
    return
  fi

  local size
  size=$(du -sk "$dir" 2>/dev/null | cut -f1)
  local size_mb
  size_mb=$(echo "scale=1; $size / 1024" | bc)

  if [ "$size" -eq 0 ]; then
    return
  fi

  echo "  ${label}: ${size_mb} MB  (${dir})"
  total_cache_size=$((total_cache_size + size))
  cache_dirs_to_delete+=("$dir")
}

# --- Browser caches ---

if [ -z "$ONLY" ] || [ "$ONLY" = "browser_caches" ]; then

echo "Browser caches:"

check_cache_dir "Puppeteer"  "$HOME/.cache/puppeteer"
check_cache_dir "Playwright" "$HOME/Library/Caches/ms-playwright"
check_cache_dir "Playwright" "$HOME/.cache/ms-playwright"
check_cache_dir "Selenium"   "$HOME/.cache/selenium"

if [ ${#cache_dirs_to_delete[@]} -eq 0 ]; then
  echo "  (none found)"
else
  total_mb=$(echo "scale=1; $total_cache_size / 1024" | bc)
  echo ""
  echo "Total: ${total_mb} MB"
  echo ""

  if $DRY_RUN; then
    echo "[dry-run] No caches were deleted."
  else
    read -rp "Delete these browser caches? [y/N] " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
      for dir in "${cache_dirs_to_delete[@]}"; do
        rm -rf "$dir"
      done
      echo "Freed ${total_mb} MB."
    else
      echo "Skipped."
    fi
  fi
fi

fi # end browser_caches

# --- Stale node_modules ---

if [ -z "$ONLY" ] || [ "$ONLY" = "node_modules" ]; then

if [ -z "$ONLY" ]; then
  echo ""
  echo "--- Stale node_modules ---"
  echo ""
fi

nm_args=(--dir="$HOME/repos")
if $DRY_RUN; then
  nm_args+=(--dry-run)
fi

"$SCRIPT_DIR/cleanup-node-modules.sh" "${nm_args[@]}"

fi # end node_modules
