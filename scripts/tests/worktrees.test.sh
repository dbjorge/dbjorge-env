#!/bin/bash

# Test script for zsh/worktrees.zsh (rmwt removal paths)
# Run with: ./worktrees.test.sh

WORKTREES_ZSH="$(cd "$(dirname "$0")/../.." && pwd)/zsh/worktrees.zsh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

tests_passed=0
tests_failed=0

pass() { echo -e "${GREEN}✓ PASS${NC}: $1"; ((tests_passed++)); }
fail() {
    echo -e "${RED}✗ FAIL${NC}: $1"
    # shellcheck disable=SC2001 # indenting every line of a multi-line detail blob
    [[ -n "$2" ]] && echo "$2" | sed 's/^/    /'
    ((tests_failed++))
}

echo "=========================================="
echo "Testing zsh/worktrees.zsh"
echo "=========================================="
echo

if ! command -v zsh >/dev/null 2>&1; then
    echo -e "${YELLOW}zsh not available; skipping${NC}"
    exit 0
fi

# Build a <root>/repos/<name> + <root>/worktrees/<name> layout, which is the shape rmwt
# requires. Echoes the root. $1 is the repo name, $2.. are worktree branches to create.
# Each worktree gets an "origin" upstream so rmwt's unpushed check passes.
make_fixture() {
    local repo="$1"; shift
    local root
    root=$(mktemp -d "${TMPDIR:-/tmp}/wt-test.XXXXXX")
    mkdir -p "$root/repos" "$root/worktrees/$repo"
    git init -q --bare "$root/$repo.git"
    git init -q -b main "$root/repos/$repo"
    git -C "$root/repos/$repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
    git -C "$root/repos/$repo" remote add origin "$root/$repo.git"
    git -C "$root/repos/$repo" push -q -u origin main
    local branch
    for branch in "$@"; do
        git -C "$root/repos/$repo" branch -q "$branch" main
        git -C "$root/repos/$repo" push -q origin "$branch"
        git -C "$root/repos/$repo" worktree add -q "$root/worktrees/$repo/$branch" "$branch"
        git -C "$root/worktrees/$repo/$branch" branch -q --set-upstream-to "origin/$branch"
    done
    echo "$root"
}

# Run zsh with worktrees.zsh sourced from $2 (a directory to cd into first) and $3 as the
# script body. compdef only exists after compinit, which a non-interactive shell hasn't run.
run_zsh() {
    local cwd="$1" body="$2"
    zsh -f -c "
        compdef() { : }
        source '$WORKTREES_ZSH'
        cd '$cwd' || exit 1
        $body
    " 2>&1
}

# Poll until the trash dir exists and is empty, up to ~10s. The purge is detached, so its
# completion is inherently asynchronous. Requiring the dir to exist keeps this from passing
# vacuously against an implementation that never trashes anything.
wait_for_empty_trash() {
    local trash="$1"
    [[ -d "$trash" ]] || return 1
    for _ in $(seq 1 100); do
        [[ -z "$(ls -A "$trash" 2>/dev/null)" ]] && return 0
        sleep 0.1
    done
    return 1
}

# --- rmwt <name>: fast path ------------------------------------------------------------

root=$(make_fixture demo feature-a)
out=$(run_zsh "$root/repos/demo" "rmwt feature-a")

if [[ -d "$root/worktrees/demo/feature-a" ]]; then
    fail "rmwt <name> removes the worktree directory" "$out"
else
    pass "rmwt <name> removes the worktree directory"
fi

if git -C "$root/repos/demo" worktree list --porcelain | grep -q "feature-a"; then
    fail "rmwt <name> unregisters the worktree" "$(git -C "$root/repos/demo" worktree list)"
else
    pass "rmwt <name> unregisters the worktree"
fi

if [[ -d "$root/repos/demo/.git/worktrees" ]]; then
    fail "rmwt <name> prunes git's worktree admin dir" "$(ls "$root/repos/demo/.git/worktrees")"
else
    pass "rmwt <name> prunes git's worktree admin dir"
fi

# Parity with `git worktree remove`, which also leaves the branch alone.
if git -C "$root/repos/demo" show-ref --verify --quiet refs/heads/feature-a; then
    pass "rmwt <name> leaves the branch in place"
else
    fail "rmwt <name> leaves the branch in place"
fi

if wait_for_empty_trash "$root/worktrees/.trash"; then
    pass "rmwt <name> purges the trashed files"
else
    fail "rmwt <name> purges the trashed files" "$(ls -A "$root/worktrees/.trash" 2>/dev/null)"
fi
rm -rf "$root"

# --- rmwt <name>: refusals are unchanged -----------------------------------------------

root=$(make_fixture demo dirty-wt)
echo "scratch" > "$root/worktrees/demo/dirty-wt/untracked.txt"
out=$(run_zsh "$root/repos/demo" "rmwt dirty-wt")
if [[ -d "$root/worktrees/demo/dirty-wt" ]] && [[ "$out" == *"uncommitted changes"* ]]; then
    pass "rmwt refuses a dirty worktree"
else
    fail "rmwt refuses a dirty worktree" "$out"
fi

out=$(run_zsh "$root/repos/demo" "rmwt --force dirty-wt")
if [[ -d "$root/worktrees/demo/dirty-wt" ]]; then
    fail "rmwt --force removes a dirty worktree" "$out"
else
    pass "rmwt --force removes a dirty worktree"
fi
wait_for_empty_trash "$root/worktrees/.trash"
rm -rf "$root"

root=$(make_fixture demo unpushed-wt)
git -C "$root/worktrees/demo/unpushed-wt" -c user.email=t@t -c user.name=t \
    commit -q --allow-empty -m local-only
out=$(run_zsh "$root/repos/demo" "rmwt unpushed-wt")
if [[ -d "$root/worktrees/demo/unpushed-wt" ]] && [[ "$out" == *"unpushed commit"* ]]; then
    pass "rmwt refuses a worktree with unpushed commits"
else
    fail "rmwt refuses a worktree with unpushed commits" "$out"
fi
rm -rf "$root"

# --- fallback to `git worktree remove` --------------------------------------------------

root=$(make_fixture demo locked-wt)
git -C "$root/repos/demo" worktree lock "$root/worktrees/demo/locked-wt"
out=$(run_zsh "$root/repos/demo" "rmwt locked-wt")
if [[ -d "$root/worktrees/demo/locked-wt" ]] && [[ "$out" == *"locked"* ]]; then
    pass "rmwt defers a locked worktree to 'git worktree remove'"
else
    fail "rmwt defers a locked worktree to 'git worktree remove'" "$out"
fi
git -C "$root/repos/demo" worktree unlock "$root/worktrees/demo/locked-wt"
rm -rf "$root"

# --- trash is self-healing ---------------------------------------------------------------

root=$(make_fixture demo feature-b)
mkdir -p "$root/worktrees/.trash/leftover-from-a-killed-purge/nested"
touch "$root/worktrees/.trash/leftover-from-a-killed-purge/nested/file.txt"
run_zsh "$root/repos/demo" "rmwt feature-b" >/dev/null
if wait_for_empty_trash "$root/worktrees/.trash"; then
    pass "rmwt sweeps leftovers from an earlier interrupted purge"
else
    fail "rmwt sweeps leftovers from an earlier interrupted purge" "$(ls -A "$root/worktrees/.trash" 2>/dev/null)"
fi
rm -rf "$root"

# --- removal from inside the worktree being removed ---------------------------------------

root=$(make_fixture demo self-wt)
out=$(run_zsh "$root/worktrees/demo/self-wt" "rmwt self-wt; pwd")
if [[ -d "$root/worktrees/demo/self-wt" ]]; then
    fail "rmwt removes the worktree it is run from" "$out"
elif [[ "$out" != *"repos/demo"* ]]; then
    fail "rmwt cd's back to the main repo when removing the current worktree" "$out"
else
    pass "rmwt removes the worktree it is run from and cd's to the main repo"
fi
wait_for_empty_trash "$root/worktrees/.trash"
rm -rf "$root"

# --- rmwt --merged -------------------------------------------------------------------------

root=$(make_fixture demo merged-1 merged-2 open-1)
# _wt_merged_branches shells out to `gh api graphql ... --jq`, so a stub that prints the
# merged branch names on stdout is a faithful stand-in for the real call's output.
stub_bin="$root/stub-bin"
mkdir -p "$stub_bin"
cat > "$stub_bin/gh" <<'STUB'
#!/bin/bash
printf '%s\n' merged-1 merged-2
STUB
chmod +x "$stub_bin/gh"
git -C "$root/repos/demo" remote set-url origin "https://github.com/example/demo.git"

out=$(PATH="$stub_bin:$PATH" run_zsh "$root/repos/demo" "rmwt --merged -y")

if [[ -d "$root/worktrees/demo/merged-1" || -d "$root/worktrees/demo/merged-2" ]]; then
    fail "rmwt --merged removes every merged worktree" "$out"
else
    pass "rmwt --merged removes every merged worktree"
fi

if [[ -d "$root/worktrees/demo/open-1" ]]; then
    pass "rmwt --merged leaves unmerged worktrees alone"
else
    fail "rmwt --merged leaves unmerged worktrees alone" "$out"
fi

registered=$(git -C "$root/repos/demo" worktree list --porcelain)
if echo "$registered" | grep -qE "merged-1|merged-2"; then
    fail "rmwt --merged unregisters the removed worktrees" "$registered"
else
    pass "rmwt --merged unregisters the removed worktrees"
fi

if echo "$registered" | grep -q "open-1"; then
    pass "rmwt --merged keeps the unmerged worktree registered"
else
    fail "rmwt --merged keeps the unmerged worktree registered" "$registered"
fi

if wait_for_empty_trash "$root/worktrees/.trash"; then
    pass "rmwt --merged purges the trashed files"
else
    fail "rmwt --merged purges the trashed files" "$(ls -A "$root/worktrees/.trash" 2>/dev/null)"
fi
rm -rf "$root"

echo
echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo -e "Tests passed: ${GREEN}$tests_passed${NC}"
echo -e "Tests failed: ${RED}$tests_failed${NC}"
echo "Total tests: $((tests_passed + tests_failed))"

if [[ $tests_failed -eq 0 ]]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
fi
