#!/usr/bin/env bash
#
# disk-usage-audit.sh
#
# Checks common disk space hogs on macOS, especially for
# Node/npm/yarn/pnpm/Docker/Claude Code workflows.
#
# Usage:
#   disk-usage-audit.sh
#
set -euo pipefail

fmt_size() {
  local kb="$1"
  if [ "$kb" -ge 1048576 ]; then
    echo "$(echo "scale=1; $kb / 1048576" | bc) GB"
  elif [ "$kb" -ge 1024 ]; then
    echo "$(echo "scale=1; $kb / 1024" | bc) MB"
  else
    echo "${kb} KB"
  fi
}

dir_size_kb() {
  local result
  result=$(du -sk "$1" 2>/dev/null | tail -1 | awk '{print $1}')
  [[ "$result" =~ ^[0-9]+$ ]] && echo "$result" || echo 0
}

check_dir() {
  local label="$1"
  local dir="$2"
  if [ -d "$dir" ]; then
    local kb
    kb=$(dir_size_kb "$dir")
    if [ "$kb" -gt 0 ]; then
      printf "  %-45s %10s  %s\n" "$label" "$(fmt_size "$kb")" "$dir"
    fi
  fi
}

check_dir_if_big() {
  local label="$1"
  local dir="$2"
  local threshold_kb="${3:-102400}"  # default 100MB
  if [ -d "$dir" ]; then
    local kb
    kb=$(dir_size_kb "$dir")
    if [ "$kb" -gt "$threshold_kb" ]; then
      printf "  %-45s %10s  %s\n" "$label" "$(fmt_size "$kb")" "$dir"
    fi
  fi
}

echo "================================================"
echo " Disk Usage Audit — $(date '+%Y-%m-%d %H:%M')"
echo "================================================"
echo ""

# Overall disk usage
echo "--- Overall disk usage ---"
df -h / | tail -1 | awk '{printf "  Disk: %s total, %s available (%s full)\n", $2, $4, $5}'
echo ""

# ============================================================
echo "--- Docker ---"
if command -v docker &>/dev/null; then
  docker_info=$(docker system df 2>/dev/null || true)
  if [ -n "$docker_info" ]; then
    echo "$docker_info" | sed 's/^/  /'
    echo ""
    echo "  Reclaimable breakdown:"
    docker system df -v 2>/dev/null | grep -E '(RECLAIMABLE|reclaimable)' | head -5 | sed 's/^/    /' || true
  else
    echo "  Docker daemon not running or not accessible"
  fi
  echo ""
  # Docker Desktop VM disk image
  check_dir "Docker Desktop disk image" "$HOME/Library/Containers/com.docker.docker/Data"
  check_dir "Docker Desktop (alt)" "$HOME/.docker/desktop"
else
  echo "  Docker not installed"
fi
echo ""

# ============================================================
echo "--- Node / npm / yarn / pnpm caches ---"
check_dir "npm cache" "$HOME/.npm/_cacache"
check_dir "npm full dir" "$HOME/.npm"
check_dir "yarn cache" "$HOME/Library/Caches/Yarn"
check_dir "yarn cache (alt)" "$HOME/.cache/yarn"
check_dir "yarn berry cache" "$HOME/.yarn/berry/cache"
check_dir "pnpm store" "$HOME/Library/pnpm/store"
check_dir "pnpm store (alt)" "$HOME/.local/share/pnpm/store"
check_dir "pnpm cache" "$HOME/.cache/pnpm"

# Global node_modules installs
for d in /usr/local/lib/node_modules "$HOME/.nvm/versions"; do
  check_dir_if_big "node versions/globals" "$d"
done

# nvm
check_dir "nvm" "$HOME/.nvm"
# fnm
check_dir "fnm" "$HOME/Library/Caches/fnm_multishells"
check_dir "fnm versions" "$HOME/Library/Application Support/fnm"
echo ""

# ============================================================
echo "--- node_modules in ~/repos (top 15 by size) ---"
if [ -d "$HOME/repos" ]; then
  find "$HOME/repos" -name node_modules -type d -maxdepth 5 -prune 2>/dev/null | while read -r nm; do
    kb=$(dir_size_kb "$nm")
    echo "$kb $nm"
  done | sort -rn | head -15 | while read -r kb path; do
    printf "  %10s  %s\n" "$(fmt_size "$kb")" "$path"
  done
fi
echo ""

# ============================================================
echo "--- Git worktrees (may contain their own node_modules) ---"
for wt_root in "$HOME/repos" "$HOME/worktrees"; do
  if [ -d "$wt_root" ]; then
    find "$wt_root" -name ".git" -type f -maxdepth 4 2>/dev/null | while read -r gitfile; do
      wt_dir=$(dirname "$gitfile")
      kb=$(dir_size_kb "$wt_dir")
      if [ "$kb" -gt 102400 ]; then
        printf "  %10s  %s\n" "$(fmt_size "$kb")" "$wt_dir"
      fi
    done
  fi
done | sort -rn | head -15
check_dir "~/worktrees total" "$HOME/worktrees"
echo ""

# ============================================================
echo "--- Claude Code ---"
check_dir "Claude Code data" "$HOME/.claude"
check_dir "Claude Code app support" "$HOME/Library/Application Support/Claude"
check_dir "Claude Code caches" "$HOME/Library/Caches/claude"
# TMPDIR worktrees and other temp files
check_dir "Claude tmp (/tmp/claude)" "/tmp/claude"
check_dir "Claude tmp (private)" "/private/tmp/claude-501"
echo ""

# ============================================================
echo "--- Browser automation caches ---"
check_dir "Puppeteer" "$HOME/.cache/puppeteer"
check_dir "Playwright" "$HOME/Library/Caches/ms-playwright"
check_dir "Playwright (alt)" "$HOME/.cache/ms-playwright"
check_dir "Selenium" "$HOME/.cache/selenium"
echo ""

# ============================================================
echo "--- macOS caches & logs ---"
check_dir_if_big "Xcode DerivedData" "$HOME/Library/Developer/Xcode/DerivedData"
check_dir_if_big "Xcode Archives" "$HOME/Library/Developer/Xcode/Archives"
check_dir_if_big "Xcode iOS DeviceSupport" "$HOME/Library/Developer/Xcode/iOS DeviceSupport"
check_dir_if_big "CoreSimulator" "$HOME/Library/Developer/CoreSimulator"
check_dir_if_big "Homebrew cache" "$HOME/Library/Caches/Homebrew"
check_dir_if_big "CocoaPods cache" "$HOME/Library/Caches/CocoaPods"
check_dir_if_big "macOS system logs" "/private/var/log"
check_dir_if_big "User logs" "$HOME/Library/Logs"
check_dir_if_big "User caches (total)" "$HOME/Library/Caches" 524288  # >512MB
check_dir_if_big "Trash" "$HOME/.Trash"
# iconservicesd cache — well-known runaway on heavy-use dev Macs.
# Sizing requires Full Disk Access on the running terminal; without it,
# du silently undercounts. If this reports huge, clear with:
#   sudo rm -rf /Library/Caches/com.apple.iconservices.store \
#               ~/Library/Caches/com.apple.iconservices.store
#   sudo killall iconservicesd iconservicesagent Dock Finder
check_dir_if_big "iconservices cache (system)" "/Library/Caches/com.apple.iconservices.store" 1048576
check_dir_if_big "iconservices cache (user)"   "$HOME/Library/Caches/com.apple.iconservices.store" 1048576
echo ""

# ============================================================
echo "--- Spotlight ---"
# /private/var/db/Spotlight-V100 is SIP-protected; even sudo+FDA can't
# size it from a booted system. Surface what we CAN see: indexing status
# and any configured exclusions. A bloated index is a common cause of
# unaccounted "System Data" — symptom is a large df-used vs du-sum gap.
if command -v mdutil &>/dev/null; then
  echo "  Indexing status:"
  mdutil -s / 2>/dev/null | sed 's/^/    /'
fi
exclusions=$(defaults read /Library/Preferences/com.apple.spotlight Exclusions 2>/dev/null || true)
if [ -z "$exclusions" ]; then
  echo "  Exclusions: (none — high-churn dev dirs like ~/repos and node_modules"
  echo "               cause Spotlight index bloat; can grow to hundreds of GB"
  echo "               that du can't see. Run scripts/spotlight-exclude-dev-dirs.sh"
  echo "               to mark them for exclusion, then 'sudo mdutil -E /' to rebuild.)"
else
  echo "  Exclusions:"
  echo "$exclusions" | sed 's/^/    /'
fi
echo ""

# ============================================================
echo "--- macOS software updates ---"
check_dir "Downloaded updates" "/Library/Updates"
check_dir "macOS Install Data" "/macOS Install Data"
check_dir "macOS Install Data (alt)" "/private/var/folders/../com.apple.SoftwareUpdate"
check_dir_if_big "SoftwareUpdate cache" "/Library/Caches/com.apple.SoftwareUpdate"
# softwareupdate can show pending updates
if command -v softwareupdate &>/dev/null; then
  pending=$(softwareupdate -l 2>&1 | grep -c "Title:" || true)
  if [ "$pending" -gt 0 ]; then
    echo "  Pending updates: $pending (downloaded updates may be using significant space)"
  fi
fi
echo ""

# ============================================================
echo "--- /tmp and /private/tmp ---"
tmp_kb=$(dir_size_kb "/private/tmp")
printf "  %-45s %10s\n" "/private/tmp total" "$(fmt_size "$tmp_kb")"
# Show big subdirs
find /private/tmp -mindepth 1 -maxdepth 1 -type d 2>/dev/null | while read -r d; do
  kb=$(dir_size_kb "$d")
  if [ "$kb" -gt 102400 ]; then
    printf "  %-45s %10s  %s\n" "  $(basename "$d")" "$(fmt_size "$kb")" "$d"
  fi
done
echo ""

# ============================================================
echo "--- Top-level ~/repos directory sizes ---"
if [ -d "$HOME/repos" ]; then
  du -sk "$HOME/repos"/*/ 2>/dev/null | sort -rn | head -20 | while read -r kb path; do
    printf "  %10s  %s\n" "$(fmt_size "$kb")" "$path"
  done
fi
echo ""

echo "================================================"
echo " Done. Review above for cleanup opportunities."
echo "================================================"
