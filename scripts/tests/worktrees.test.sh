#!/bin/bash

# Test script for zsh/worktrees.zsh (rmwt removal paths)
# Run with: ./worktrees.test.sh

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORKTREES_ZSH="$REPO_ROOT/zsh/worktrees.zsh"

# gwt shells out to the `git wt` alias; layer this checkout's definition over whatever
# version is installed globally so the suite tests the code under review.
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=include.path GIT_CONFIG_VALUE_0="$REPO_ROOT/gitconfig_global.txt"

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

# --- gwt --from ------------------------------------------------------------------------

# Fixture with a "base" branch one commit ahead of main, so a worktree's starting point
# is distinguishable.
make_from_fixture() {
    local root
    root=$(make_fixture demo)
    git -C "$root/repos/demo" branch -q base main
    git -C "$root/repos/demo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m on-main
    local wt
    wt=$(mktemp -d "${TMPDIR:-/tmp}/wt-base.XXXXXX")
    rmdir "$wt"
    git -C "$root/repos/demo" worktree add -q "$wt" base
    git -C "$wt" -c user.email=t@t -c user.name=t commit -q --allow-empty -m on-base
    git -C "$root/repos/demo" worktree remove "$wt"
    echo "$root"
}

root=$(make_from_fixture)
out=$(run_zsh "$root/repos/demo" "gwt feature-new --from base >/dev/null; echo \"PWD=\$PWD\"")
if echo "$out" | grep -q "^PWD=.*worktrees/demo/feature-new$" \
    && [[ "$(git -C "$root/worktrees/demo/feature-new" rev-parse HEAD 2>/dev/null)" == "$(git -C "$root/repos/demo" rev-parse base)" ]]; then
    pass "gwt <branch> --from <base> branches the new worktree off <base>"
else
    fail "gwt <branch> --from <base> branches the new worktree off <base>" "$out"
fi
upstream="$(git -C "$root/repos/demo" config branch.feature-new.remote)/$(git -C "$root/repos/demo" config branch.feature-new.merge)"
if [[ "$upstream" == "origin/refs/heads/feature-new" ]]; then
    pass "gwt --from still preconfigures origin/<branch> as the upstream"
else
    fail "gwt --from still preconfigures origin/<branch> as the upstream" "$upstream"
fi
rm -rf "$root"

root=$(make_from_fixture)
out=$(run_zsh "$root/repos/demo" "gwt --from base feature-new >/dev/null; echo \"PWD=\$PWD\"")
if echo "$out" | grep -q "^PWD=.*worktrees/demo/feature-new$" \
    && [[ "$(git -C "$root/worktrees/demo/feature-new" rev-parse HEAD 2>/dev/null)" == "$(git -C "$root/repos/demo" rev-parse base)" ]]; then
    pass "gwt --from <base> <branch> accepts --from before the branch"
else
    fail "gwt --from <base> <branch> accepts --from before the branch" "$out"
fi
rm -rf "$root"

root=$(make_from_fixture)
git -C "$root/repos/demo" branch -q existing main
out=$(run_zsh "$root/repos/demo" "gwt existing --from base; echo \"rc=\$?\"")
if echo "$out" | grep -q "^rc=1$" && [[ ! -e "$root/worktrees/demo/existing" ]]; then
    pass "gwt --from refuses a branch that already exists"
else
    fail "gwt --from refuses a branch that already exists" "$out"
fi
rm -rf "$root"

root=$(make_from_fixture)
out=$(run_zsh "$root/repos/demo" "gwt feature-new --from no-such-ref; echo \"rc=\$?\"")
if echo "$out" | grep -q "^rc=1$" && [[ ! -e "$root/worktrees/demo/feature-new" ]] \
    && ! git -C "$root/repos/demo" show-ref --verify --quiet refs/heads/feature-new; then
    pass "gwt --from an unknown ref creates nothing"
else
    fail "gwt --from an unknown ref creates nothing" "$out"
fi
rm -rf "$root"

root=$(make_from_fixture)
out=$(run_zsh "$root/repos/demo" "gwt feature-new --from; echo \"rc=\$?\"")
if echo "$out" | grep -q "^rc=1$" && [[ ! -e "$root/worktrees/demo/feature-new" ]]; then
    pass "gwt --from with no value is a usage error"
else
    fail "gwt --from with no value is a usage error" "$out"
fi
rm -rf "$root"

# --- completion -------------------------------------------------------------------------

# Run completion function $2 from $1 with the command line $3.. (the last word is the one
# being completed), printing the candidates it offers. compadd is stubbed to print what
# follows "--".
complete_in() {
    local cwd="$1" fn="$2"; shift 2
    local w quoted=""
    for w in "$@"; do quoted+=" '$w'"; done
    run_zsh "$cwd" "
        compadd() { while [[ \$# -gt 0 && \$1 != -- ]]; do shift; done; shift; print -l -- \"\$@\" }
        words=($quoted)
        CURRENT=\${#words}
        $fn
    "
}

root=$(make_from_fixture)
git -C "$root/repos/demo" fetch -q origin
git -C "$root/repos/demo" remote set-head origin main
out=$(complete_in "$root/repos/demo" _gwt gwt feature-new --from "")
if echo "$out" | grep -qx "base" && echo "$out" | grep -qx "main" && echo "$out" | grep -qx "origin/main" \
    && ! echo "$out" | grep -qx "origin"; then
    pass "gwt completes local and remote branch names after --from"
else
    fail "gwt completes local and remote branch names after --from" "$out"
fi

out=$(complete_in "$root/repos/demo" _gwt gwt feature-new --)
if echo "$out" | grep -qx -- "--from"; then
    pass "gwt completes the --from flag"
else
    fail "gwt completes the --from flag" "$out"
fi

out=$(complete_in "$root/repos/demo" _rmwt rmwt --)
if ! echo "$out" | grep -qx -- "--from"; then
    pass "rmwt does not offer --from"
else
    fail "rmwt does not offer --from" "$out"
fi
rm -rf "$root"

# --- Herdr registration -----------------------------------------------------------------

# Build a fake `herdr` in $1 that appends its argv to $1/calls.log, and answers
# `worktree list` with a record claiming $2 is open as workspace w7.
make_fake_herdr() {
    local dir="$1" wt_path="$2"
    cat > "$dir/herdr" <<EOF
#!/bin/bash
echo "\$* (from \$PWD)" >> "$dir/calls.log"
if [ "\$1" = "worktree" ] && [ "\$2" = "list" ]; then
  printf '%s' '{"result":{"worktrees":[{"path":"$wt_path","open_workspace_id":"w7"}]}}'
fi
exit 0
EOF
    chmod +x "$dir/herdr"
}

# gwt/gwtpr stay plain cd helpers even inside Herdr; hwt/hwtpr are the Herdr variants.
root=$(make_fixture demo)
fake=$(mktemp -d "${TMPDIR:-/tmp}/wt-fake.XXXXXX")
make_fake_herdr "$fake" "unused"
out=$(run_zsh "$root/repos/demo" "HERDR_ENV=1 HERDR_BIN_PATH='$fake/herdr' gwt feature-new >/dev/null; echo \"PWD=\$PWD\"")

if [[ ! -e "$fake/calls.log" ]] && echo "$out" | grep -q "^PWD=.*worktrees/demo/feature-new$"; then
    pass "gwt inside Herdr cd's into the worktree without calling herdr"
else
    fail "gwt inside Herdr cd's into the worktree without calling herdr" "$out
$(cat "$fake/calls.log" 2>/dev/null)"
fi
rm -rf "$root" "$fake"

# hwt <branch> opens the checkout as a Herdr workspace and leaves the calling shell alone
root=$(make_fixture demo)
fake=$(mktemp -d "${TMPDIR:-/tmp}/wt-fake.XXXXXX")
make_fake_herdr "$fake" "unused"
out=$(run_zsh "$root/repos/demo" "HERDR_ENV=1 HERDR_WORKSPACE_ID=w3 HERDR_BIN_PATH='$fake/herdr' hwt feature-new >/dev/null; echo \"PWD=\$PWD\"")
calls=$(cat "$fake/calls.log" 2>/dev/null)

# Herdr derives the parent workspace's repo from its pane cwd, so the open must happen
# after the shell is back in the repo, not while it is still inside the new worktree.
if echo "$calls" | grep -q "worktree open --workspace w3 --path .*worktrees/demo/feature-new --focus (from .*repos/demo)" \
    && echo "$out" | grep -q "^PWD=.*repos/demo$"; then
    pass "hwt opens the worktree under the current Herdr workspace and stays in the original dir"
else
    fail "hwt opens the worktree under the current Herdr workspace and stays in the original dir" "$out
$calls"
fi
rm -rf "$root" "$fake"

# hwt forwards --from to gwt
root=$(make_from_fixture)
fake=$(mktemp -d "${TMPDIR:-/tmp}/wt-fake.XXXXXX")
make_fake_herdr "$fake" "unused"
run_zsh "$root/repos/demo" "HERDR_ENV=1 HERDR_WORKSPACE_ID=w3 HERDR_BIN_PATH='$fake/herdr' hwt feature-new --from base" >/dev/null
if [[ "$(git -C "$root/worktrees/demo/feature-new" rev-parse HEAD 2>/dev/null)" == "$(git -C "$root/repos/demo" rev-parse base)" ]] \
    && grep -q "worktree open --workspace w3 --path .*worktrees/demo/feature-new --focus" "$fake/calls.log"; then
    pass "hwt <branch> --from <base> branches off <base> and opens it in Herdr"
else
    fail "hwt <branch> --from <base> branches off <base> and opens it in Herdr" "$(cat "$fake/calls.log" 2>/dev/null)"
fi
rm -rf "$root" "$fake"

# hwt outside Herdr refuses before creating anything
root=$(make_fixture demo)
fake=$(mktemp -d "${TMPDIR:-/tmp}/wt-fake.XXXXXX")
make_fake_herdr "$fake" "unused"
# HERDR_ENV is cleared explicitly: the suite itself may be running inside a Herdr pane,
# and zsh -f still inherits the exported environment.
run_zsh "$root/repos/demo" "HERDR_ENV= HERDR_BIN_PATH='$fake/herdr' hwt feature-new" >/dev/null

if [[ ! -e "$fake/calls.log" && ! -e "$root/worktrees/demo/feature-new" ]]; then
    pass "hwt outside Herdr does nothing"
else
    fail "hwt outside Herdr does nothing" "$(ls "$root/worktrees/demo")"
fi
rm -rf "$root" "$fake"

# gwtpr inside Herdr does not call herdr
root=$(make_fixture demo)
fake=$(mktemp -d "${TMPDIR:-/tmp}/wt-fake.XXXXXX")
make_fake_herdr "$fake" "unused"
run_zsh "$root/repos/demo" "
    gh() {
        case \"\$1 \$2\" in
            'pr view') echo 'feature/from-pr' ;;
            'pr checkout') return 0 ;;
        esac
    }
    HERDR_ENV=1 HERDR_BIN_PATH='$fake/herdr' gwtpr 42
" >/dev/null

if [[ ! -e "$fake/calls.log" ]]; then
    pass "gwtpr inside Herdr does not call herdr"
else
    fail "gwtpr inside Herdr does not call herdr" "$(cat "$fake/calls.log")"
fi
rm -rf "$root" "$fake"

# hwtpr opens the PR checkout in Herdr, after gh has checked it out, and stays put
root=$(make_fixture demo)
fake=$(mktemp -d "${TMPDIR:-/tmp}/wt-fake.XXXXXX")
make_fake_herdr "$fake" "unused"
out=$(run_zsh "$root/repos/demo" "
    gh() {
        case \"\$1 \$2\" in
            'pr view') echo 'feature/from-pr' ;;
            'pr checkout') echo \"checkout in \$PWD\" >> '$fake/calls.log' ;;
        esac
    }
    HERDR_ENV=1 HERDR_WORKSPACE_ID=w3 HERDR_BIN_PATH='$fake/herdr' hwtpr 42 >/dev/null
    echo \"PWD=\$PWD\"
")
calls=$(cat "$fake/calls.log" 2>/dev/null)

if echo "$calls" | grep -q "^checkout in .*worktrees/demo/from-pr$" \
    && echo "$calls" | grep -q "worktree open --workspace w3 --path .*from-pr --focus (from .*repos/demo)" \
    && echo "$out" | grep -q "^PWD=.*repos/demo$"; then
    pass "hwtpr opens the PR worktree under the current Herdr workspace and stays in the original dir"
else
    fail "hwtpr opens the PR worktree under the current Herdr workspace and stays in the original dir" "$out
$calls"
fi
rm -rf "$root" "$fake"

# rmwt closes the Herdr workspace before trashing the checkout, since Herdr
# resolves a workspace by path and the rename breaks that match.
root=$(make_fixture demo feature-a)
fake=$(mktemp -d "${TMPDIR:-/tmp}/wt-fake.XXXXXX")
make_fake_herdr "$fake" "$(cd "$root/worktrees/demo/feature-a" && pwd -P)"
run_zsh "$root/repos/demo" "HERDR_ENV=1 HERDR_BIN_PATH='$fake/herdr' rmwt feature-a" >/dev/null
calls=$(cat "$fake/calls.log" 2>/dev/null)

if echo "$calls" | grep -q "workspace close w7"; then
    pass "rmwt inside Herdr closes the worktree's workspace"
else
    fail "rmwt inside Herdr closes the worktree's workspace" "$calls"
fi
rm -rf "$root" "$fake"

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
