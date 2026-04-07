#!/usr/bin/env bash
#
# cleanup-node-modules.sh
#
# Finds git repos that haven't had any file changes in a given period and
# deletes their node_modules directories (including workspace packages).
#
# If --dir points to a single git repo, it checks that repo. If it points
# to a directory containing multiple git repos, it checks each one.
#
# Each git repo is treated atomically: either all of its node_modules
# directories are deleted, or none are.
#
# Usage:
#   cleanup-node-modules.sh [--dry-run] [--days=N] [--dir=PATH]
#
# Options:
#   --dry-run   List what would be deleted without actually deleting anything
#   --days=N    Number of days of inactivity before cleanup (default: 30)
#   --dir=PATH  Base directory to scan (default: current working directory)
#
set -euo pipefail

DAYS=30
DRY_RUN=false
BASE_DIR="$PWD"

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --days=*) DAYS="${arg#--days=}" ;;
    --dir=*) BASE_DIR="${arg#--dir=}" ;;
    *) echo "Usage: $0 [--dry-run] [--days=N] [--dir=PATH]"; exit 1 ;;
  esac
done

BASE_DIR="$(cd "$BASE_DIR" && pwd -P)"

# Create a reference file with the cutoff timestamp for find -newer
ref_file=$(mktemp)
touch -t "$(date -v-"${DAYS}"d '+%Y%m%d%H%M.%S' 2>/dev/null || date -d "${DAYS} days ago" '+%Y%m%d%H%M.%S')" "$ref_file"
trap 'rm -f "$ref_file"' EXIT

# Collect git repos to check: either BASE_DIR itself, or its immediate subdirectories
repos=()
if [ -d "$BASE_DIR/.git" ]; then
  repos+=("$BASE_DIR")
else
  for dir in "$BASE_DIR"/*/; do
    [ -d "$dir/.git" ] || continue
    repos+=("${dir%/}")
  done
fi

if [ ${#repos[@]} -eq 0 ]; then
  echo "No git repositories found in $BASE_DIR"
  exit 0
fi

total_size=0
total_nm=0
# Parallel arrays: repo paths and their node_modules (newline-separated)
repo_order=()
repo_nm_lists=()

for repo in "${repos[@]}"; do
  repo_name="${repo#"$BASE_DIR"/}"
  # If BASE_DIR is the repo itself, use its basename
  [[ "$repo" == "$BASE_DIR" ]] && repo_name="$(basename "$repo")"

  # Check if any non-node_modules file was modified recently
  recent=$(find "$repo" \
    -not -path '*/node_modules/*' \
    -not -path '*/.git/*' \
    -not -name '.DS_Store' \
    -type f \
    -newer "$ref_file" \
    -print -quit 2>/dev/null)

  if [ -n "$recent" ]; then
    continue
  fi

  # Find all node_modules dirs in this repo, skipping any that are checked into git
  nm_dirs=()
  while IFS= read -r nm_dir; do
    if git -C "$repo" check-ignore -q "$nm_dir" 2>/dev/null; then
      nm_dirs+=("$nm_dir")
    fi
  done < <(find "$repo" -name node_modules -type d -prune 2>/dev/null)

  [ ${#nm_dirs[@]} -eq 0 ] && continue

  # Print this repo's results as we find them
  repo_size=0
  nm_lines=""
  for nm in "${nm_dirs[@]}"; do
    size=$(du -sk "$nm" 2>/dev/null | cut -f1)
    repo_size=$((repo_size + size))
    size_mb=$(echo "scale=1; $size / 1024" | bc)
    nm_lines+="    ${nm#"$repo"/}  (${size_mb} MB)"$'\n'
  done
  repo_size_mb=$(echo "scale=1; $repo_size / 1024" | bc)

  # Print header on first match
  if [ $total_nm -eq 0 ]; then
    echo "Inactive repos (no changes in ${DAYS}+ days) with node_modules:"
    echo ""
  fi

  echo "  ${repo_name}  (${repo_size_mb} MB total, ${#nm_dirs[@]} node_modules)"
  printf "%s" "$nm_lines"

  total_size=$((total_size + repo_size))
  total_nm=$((total_nm + ${#nm_dirs[@]}))
  repo_order+=("$repo")
  repo_nm_lists+=("$(printf '%s\n' "${nm_dirs[@]}")")
done

if [ $total_nm -eq 0 ]; then
  echo "No node_modules directories to clean up (all repos active within ${DAYS} days)."
  exit 0
fi

total_mb=$(echo "scale=1; $total_size / 1024" | bc)
echo ""
echo "Total: ${total_nm} node_modules directory(ies), ${total_mb} MB"
echo ""

if $DRY_RUN; then
  echo "[dry-run] No directories were deleted."
  exit 0
fi

read -rp "Delete all listed directories? [y/N] " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 0
fi
echo ""

for i in "${!repo_order[@]}"; do
  repo="${repo_order[$i]}"
  repo_name="${repo#"$BASE_DIR"/}"
  [[ "$repo" == "$BASE_DIR" ]] && repo_name="$(basename "$repo")"

  while IFS= read -r nm; do
    [ -z "$nm" ] && continue
    # Safety check: ensure the directory is under BASE_DIR and is a node_modules directory
    resolved=$(cd "$nm" && pwd -P)
    if [[ "$resolved" != "$BASE_DIR"/* || "$(basename "$resolved")" != "node_modules" ]]; then
      echo "FATAL SCRIPT BUG: refusing to delete '$resolved' — not under BASE_DIR or not a node_modules directory" >&2
      exit 1
    fi
    rm -rf "$nm"
  done <<< "${repo_nm_lists[$i]}"
  echo "Cleaned: ${repo_name}"
done

echo ""
echo "Done. Freed ~${total_mb} MB."
