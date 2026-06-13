# Worktree helpers for the ~/repos/<repo> + ~/worktrees/<repo>/<branch> layout.
#   gr     cd to the main repo root from anywhere in a repo or worktree
#   gwt    create/switch worktrees (numbered picker with no args)
#   gwtpr  create a worktree for a GitHub PR
#   rmwt   remove a worktree (picker, or --merged batch)
#   claude launcher wrapper; in a worktree, grants the main-repo .git as
#          sandbox-writable so `git add`/`git commit` work there
# Sourced from .zshrc after compinit, which the compdef calls at the bottom need.

# Wrap the `claude` launcher so that, inside a git worktree, the worktree's
# main-repo .git (which lives outside the worktree dir, under ~/repos/<repo>/.git)
# is granted as a sandbox-writable path for that session — letting sandboxed
# `git add`/`git commit` work in the worktree. Only that one repo's .git is
# granted, passed as a per-launch `--settings` arg (merged with your normal
# settings; nothing is persisted to disk). No-op outside a worktree: a normal
# ~/repos/<repo> checkout already has its .git under the writable project root.
# `command claude` calls the real binary, so the function doesn't recurse.
# Requires git >= 2.31 (--path-format) and jq.
claude() {
  local common gitdir args=()
  common=$(command git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
  gitdir=$(command git rev-parse --path-format=absolute --git-dir 2>/dev/null)
  if [[ -n "$common" && "$common" != "$gitdir" ]]; then
    args=(--settings "$(jq -nc --arg p "${common%/}/" \
      '{sandbox:{filesystem:{allowWrite:[$p]}}}')")
  fi
  command claude "${args[@]}" "$@"
}

# cd to the original repo root (~/repos/<repo>) from a repo or worktree
gr() {
  local root parent
  root=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "Not in a git repo" >&2; return 1; }
  parent=$(dirname "$root")
  if [[ "$(basename "$parent")" == "repos" ]]; then
    cd "$root"
  elif [[ "$(basename "$(dirname "$parent")")" == "worktrees" ]]; then
    cd "$(dirname "$(dirname "$parent")")/repos/$(basename "$parent")"
  else
    echo "Error: unable to determine main repo directory" >&2; return 1
  fi
}

# Resolve the GitHub owner/repo whose PRs are the base for this clone, as "owner/name".
# Prefers the remote gh has resolved as the PR base (recorded in git config as
# remote.<name>.gh-resolved after using gh — correct for fork clones where PRs target
# `upstream`, not `origin`), else origin, else the first remote. Pure git-config/URL
# parsing: no network call and no risk of an interactive gh prompt. Empty if unresolvable.
_wt_base_repo() {
  local repo_dir="$1" line key rname url
  line=$(git -C "$repo_dir" config --get-regexp '^remote\..*\.gh-resolved$' 2>/dev/null | head -1)
  if [[ -n "$line" ]]; then
    key="${line%% *}"; rname="${key#remote.}"; rname="${rname%.gh-resolved}"
  fi
  [[ -z "$rname" ]] && rname=origin
  url=$(git -C "$repo_dir" remote get-url "$rname" 2>/dev/null)
  [[ -z "$url" ]] && url=$(git -C "$repo_dir" remote get-url "$(git -C "$repo_dir" remote 2>/dev/null | head -1)" 2>/dev/null)
  [[ "$url" =~ 'github\.com[:/]([^/]+)/([^/]+)$' ]] || return 0
  print -r -- "${match[1]}/${match[2]%.git}"
}

# Given a git working dir ($1) and a list of branch names ($2..), print the subset
# whose PR is already merged, one per line. Uses a SINGLE GraphQL call with one aliased
# pullRequests(headRefName:...) field per branch, so cost scales with the number of
# worktrees (a handful) rather than the repo's total PR count. Empty when gh is
# unavailable/offline or the GitHub owner/repo can't be resolved.
_wt_merged_branches() {
  command -v gh >/dev/null 2>&1 || return 0
  local repo_dir="$1"; shift
  local -a branches=("$@")
  (( ${#branches} )) || return 0
  local owner_repo
  owner_repo=$(_wt_base_repo "$repo_dir") || return 0
  [[ -n "$owner_repo" ]] || return 0
  local owner="${owner_repo%%/*}" name="${owner_repo##*/}"
  local q="query{repository(owner:\"$owner\",name:\"$name\"){" i
  for i in {1..${#branches}}; do
    q+="a$i:pullRequests(headRefName:\"${branches[$i]}\",states:MERGED,first:1){nodes{headRefName}}"
  done
  q+="}}"
  gh api graphql -f query="$q" --jq '.data.repository | to_entries[] | .value.nodes[].headRefName' 2>/dev/null
}

# Print status suffix labels for a worktree dir, e.g. " [dirty] [unpushed]". Empty
# when clean. Multiple labels may apply.
#   [dirty]    uncommitted changes in the worktree
#   [unpushed] local commits not pushed upstream (or no upstream configured)
#   [stale]    upstream has commits not pulled into local
#   [merged]   branch's PR has already been merged/squashed
# $2 is the newline-separated set of merged branch names (from _wt_merged_branches);
# [merged] is labeled only when this worktree's branch is in that set, so callers make
# one gh call up front rather than one per worktree.
_wt_status() {
  local target="$1" merged="$2" labels="" upstream ahead behind branch
  [[ -d "$target" ]] || return 0
  if [[ -n "$(git -C "$target" status --porcelain 2>/dev/null)" ]]; then
    labels+=" [dirty]"
  fi
  upstream=$(git -C "$target" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)
  if [[ -z "$upstream" ]]; then
    labels+=" [unpushed]"
  else
    ahead=$(git -C "$target" rev-list --count "@{u}..HEAD" 2>/dev/null)
    behind=$(git -C "$target" rev-list --count "HEAD..@{u}" 2>/dev/null)
    [[ -n "$ahead" && "$ahead" -gt 0 ]] && labels+=" [unpushed]"
    [[ -n "$behind" && "$behind" -gt 0 ]] && labels+=" [stale]"
  fi
  if [[ -n "$merged" ]]; then
    branch=$(git -C "$target" symbolic-ref --quiet --short HEAD 2>/dev/null)
    if [[ -n "$branch" ]]; then
      local -a merged_arr
      merged_arr=("${(@f)merged}")
      (( ${merged_arr[(Ie)$branch]} )) && labels+=" [merged]"
    fi
  fi
  print -r -- "$labels"
}

# Collect the branch name of every worktree dir under $1 (the worktrees parent dir),
# then resolve which are merged in one call. Prints the merged-branch set for passing
# to _wt_status. $2.. are the worktree leaf names to inspect.
_wt_merged_set() {
  local wt_dir="$1"; shift
  local -a names=("$@") branches
  local n b
  for n in $names; do
    b=$(git -C "$wt_dir/$n" symbolic-ref --quiet --short HEAD 2>/dev/null)
    [[ -n "$b" ]] && branches+=("$b")
  done
  (( ${#branches} )) || return 0
  _wt_merged_branches "$wt_dir/${names[1]}" $branches
}

# git worktree wrapper - creates worktree + branch if needed, then cd's into it
# with no args: cd to worktree root (if in a worktree) or prompt for a worktree name
gwt() {
  if [[ $# -eq 0 ]]; then
    local root parent
    root=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "Not in a git repo" >&2; return 1; }
    parent=$(dirname "$root")
    if [[ "$(basename "$(dirname "$parent")")" == "worktrees" ]]; then
      cd "$root"
    else
      local repo wt_dir choice
      repo=$(basename "$root")
      wt_dir="$(dirname "$parent")/worktrees/$repo"
      if [[ ! -d "$wt_dir" ]] || [[ -z "$(ls -A "$wt_dir" 2>/dev/null)" ]]; then
        echo "No worktrees found for $repo" >&2; return 1
      fi
      echo "Available worktrees for $repo:"
      local -a wts
      wts=("$wt_dir"/*(/:t))
      local merged_set i
      merged_set=$(_wt_merged_set "$wt_dir" $wts)
      for i in {1..${#wts[@]}}; do
        echo "  $i) ${wts[$i]}$(_wt_status "$wt_dir/${wts[$i]}" "$merged_set")"
      done
      echo -n "Select worktree: "
      read choice
      if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#wts[@]} )); then
        cd "$wt_dir/${wts[$choice]}"
      else
        echo "Invalid selection" >&2; return 1
      fi
    fi
  else
    local target
    target=$(git wt "$@") || return 1
    cd "$target"
  fi
}
_gwt() {
  local root repo parent wt_dir
  root=$(git rev-parse --show-toplevel 2>/dev/null) || return
  repo=$(basename "$root")
  parent=$(dirname "$root")
  wt_dir="${parent}/../worktrees/${repo}"
  if [[ -d "$wt_dir" ]]; then
    compadd -- "$wt_dir"/*(/:t)
  fi
}

# Worktree for a GitHub PR: gwtpr [pr-number]. With no args, shows a numbered
# picker of the 30 most recent open PRs. Creates ../worktrees/<repo>/<dir>
# (detached) where <dir> is the head branch's leaf segment truncated to 32 chars,
# cd's in, and runs `gh pr checkout` so the branch is set up correctly (handles
# forks). If the worktree already exists and is dirty, bails without cd.
gwtpr() {
  local pr
  if [[ $# -eq 0 ]]; then
    local pr_list_output
    pr_list_output=$(gh pr list --limit 30 --json number,title,author -q '.[] | "\(.number)\t\(.title) (@\(.author.login))"' 2>/dev/null) || {
      echo "Failed to list PRs" >&2; return 1
    }
    if [[ -z "$pr_list_output" ]]; then
      echo "No open PRs found" >&2; return 1
    fi
    local -a pr_lines
    pr_lines=("${(@f)pr_list_output}")
    echo "Recent open PRs:"
    local i
    for i in {1..${#pr_lines[@]}}; do
      printf "  %2d) #%s\n" "$i" "${pr_lines[$i]//$'\t'/  }"
    done
    local choice
    echo -n "Select PR: "
    read choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#pr_lines[@]} )); then
      pr="${pr_lines[$choice]%%$'\t'*}"
    else
      echo "Invalid selection" >&2; return 1
    fi
  elif [[ $# -eq 1 ]]; then
    pr="$1"
  else
    echo "Usage: gwtpr [pr-number]" >&2; return 1
  fi
  local root repo parent
  root=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "Not in a git repo" >&2; return 1; }
  repo=$(basename "$root")
  parent=$(dirname "$root")
  if [[ "$(basename "$parent")" != "repos" ]]; then
    echo "Error: repo must be inside a 'repos' directory" >&2; return 1
  fi
  local branch
  branch=$(gh pr view "$pr" --json headRefName -q .headRefName 2>/dev/null) || {
    echo "Failed to look up PR #$pr" >&2; return 1
  }
  local dir="${branch##*/}"
  dir="${dir:0:32}"
  local target="$parent/../worktrees/$repo/$dir"
  if [[ -d "$target" ]]; then
    if [[ -n "$(git -C "$target" status --porcelain)" ]]; then
      echo "Worktree at $target has uncommitted changes; bailing" >&2; return 1
    fi
    cd "$target" || return 1
  else
    mkdir -p "$(dirname "$target")"
    git worktree add --detach "$target" >&2 || return 1
    cd "$target" || return 1
  fi
  gh pr checkout "$pr"
}
_gwtpr() {
  local -a prs
  prs=("${(@f)$(gh pr list --limit 30 --json number,title -q '.[] | "\(.number):\(.title)"' 2>/dev/null)}")
  if (( ${#prs[@]} > 0 )); then
    _describe -t prs 'open PRs' prs
  fi
}

# Remove a worktree under ../worktrees/<repo>/. `rmwt <name>` removes that worktree;
# bare `rmwt` shows a numbered picker (entries that are dirty/unpushed and so need
# --force are marked "<n>*)"; enter "<n> --force" to force-remove one of them).
# `rmwt --merged` removes every merged, non-dirty
# worktree (prompts for confirmation unless -y is given). Works from the main repo or
# from inside a worktree; when run inside a worktree the picker lists "current (<name>)"
# first and selecting it cd's back to the main repo before removing. Refuses if dirty or
# has unpushed commits (no upstream counts as unpushed) unless --force/-f is passed.
rmwt() {
  local force=0 merged=0 assume_yes=0
  while [[ "$1" == -* ]]; do
    case "$1" in
      --force|-f) force=1 ;;
      --merged) merged=1 ;;
      -y|--yes) assume_yes=1 ;;
      *) echo "Unknown option: $1" >&2; return 1 ;;
    esac
    shift
  done
  local root repo parent wt_dir main_repo_dir cur_wt=""
  root=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "Not in a git repo" >&2; return 1; }
  parent=$(dirname "$root")
  if [[ "$(basename "$parent")" == "repos" ]]; then
    repo=$(basename "$root")
    main_repo_dir="$root"
    wt_dir="$parent/../worktrees/$repo"
  elif [[ "$(basename "$(dirname "$parent")")" == "worktrees" ]]; then
    repo=$(basename "$parent")
    wt_dir="$parent"
    main_repo_dir="$(dirname "$(dirname "$parent")")/repos/$repo"
    cur_wt=$(basename "$root")
  else
    echo "Error: must run from main repo (~/repos/<repo>) or a worktree" >&2; return 1
  fi
  if (( merged )); then
    if [[ ! -d "$wt_dir" ]] || [[ -z "$(ls -A "$wt_dir" 2>/dev/null)" ]]; then
      echo "No worktrees found for $repo" >&2; return 1
    fi
    local -a all candidates
    all=("$wt_dir"/*(/:t))
    local w wt_st merged_set
    merged_set=$(_wt_merged_set "$wt_dir" $all)
    for w in $all; do
      wt_st=$(_wt_status "$wt_dir/$w" "$merged_set")
      if [[ "$wt_st" == *"[merged]"* && "$wt_st" != *"[dirty]"* ]]; then
        candidates+=("$w")
      fi
    done
    if (( ${#candidates[@]} == 0 )); then
      echo "No merged, non-dirty worktrees found for $repo"; return 0
    fi
    echo "Merged worktrees to remove for $repo:"
    for w in $candidates; do
      if [[ "$w" == "$cur_wt" ]]; then echo "  - current ($w)"; else echo "  - $w"; fi
    done
    if (( ! assume_yes )); then
      local reply
      echo -n "Remove these ${#candidates[@]} worktree(s)? [y/N] "
      read reply
      if [[ "$reply" != [yY]* ]]; then echo "Aborted"; return 1; fi
    fi
    local -a rm_args
    (( force )) && rm_args+=(--force)
    local failed=0
    for w in $candidates; do
      if [[ "$w" == "$cur_wt" ]]; then
        cd "$main_repo_dir" || { echo "Failed to cd to main repo dir $main_repo_dir" >&2; return 1; }
      fi
      if git worktree remove "${rm_args[@]}" "$wt_dir/$w"; then
        echo "Removed worktree $wt_dir/$w"
      else
        echo "Failed to remove $wt_dir/$w" >&2; failed=1
      fi
    done
    return $failed
  fi
  local name
  if [[ $# -eq 0 ]]; then
    if [[ ! -d "$wt_dir" ]] || [[ -z "$(ls -A "$wt_dir" 2>/dev/null)" ]]; then
      echo "No worktrees found for $repo" >&2; return 1
    fi
    local -a wts all
    all=("$wt_dir"/*(/:t))
    # put the current worktree first when we're inside one
    if [[ -n "$cur_wt" ]]; then
      wts=("$cur_wt")
      local w
      for w in $all; do
        [[ "$w" == "$cur_wt" ]] || wts+=("$w")
      done
    else
      wts=($all)
    fi
    echo "Available worktrees for $repo:"
    local merged_set i st marker any_star=0
    merged_set=$(_wt_merged_set "$wt_dir" $wts)
    for i in {1..${#wts[@]}}; do
      st=$(_wt_status "$wt_dir/${wts[$i]}" "$merged_set")
      # mark entries that would be refused without --force (dirty or unpushed)
      if [[ "$st" == *"[dirty]"* || "$st" == *"[unpushed]"* ]]; then
        marker="*"; any_star=1
      else
        marker=""
      fi
      if [[ "${wts[$i]}" == "$cur_wt" ]]; then
        echo "  $i$marker) current (${wts[$i]})$st"
      else
        echo "  $i$marker) ${wts[$i]}$st"
      fi
    done
    local choice prompt="Select worktree to remove: "
    (( any_star )) && prompt="Select worktree to remove (use --force for * entries): "
    echo -n "$prompt"
    read choice
    # accept "<n>" or "<n> --force"/"<n> -f" to force-remove an unpushed/dirty entry
    local -a parts
    parts=(${=choice})
    if (( ${#parts} >= 2 )); then
      if [[ ${#parts} -gt 2 || ( "${parts[2]}" != "--force" && "${parts[2]}" != "-f" ) ]]; then
        echo "Invalid selection" >&2; return 1
      fi
      force=1
    fi
    if [[ "${parts[1]}" =~ ^[0-9]+$ ]] && (( parts[1] >= 1 && parts[1] <= ${#wts[@]} )); then
      name="${wts[${parts[1]}]}"
    else
      echo "Invalid selection" >&2; return 1
    fi
  else
    name="$1"
  fi
  local target="$wt_dir/$name"
  if [[ ! -d "$target" ]]; then
    echo "Worktree '$name' not found at $target" >&2; return 1
  fi
  if (( ! force )); then
    if [[ -n "$(git -C "$target" status --porcelain)" ]]; then
      echo "Worktree '$name' has uncommitted changes; rerun with --force to remove" >&2; return 1
    fi
    local upstream unpushed
    upstream=$(git -C "$target" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)
    if [[ -z "$upstream" ]]; then
      echo "Worktree '$name' has no upstream (possible unpushed commits); rerun with --force to remove" >&2; return 1
    fi
    unpushed=$(git -C "$target" rev-list "@{u}..HEAD" --count 2>/dev/null)
    if [[ -n "$unpushed" && "$unpushed" -gt 0 ]]; then
      echo "Worktree '$name' has $unpushed unpushed commit(s); rerun with --force to remove" >&2; return 1
    fi
  fi
  # can't remove the worktree we're standing in; step back to the main repo first
  if [[ "$name" == "$cur_wt" ]]; then
    cd "$main_repo_dir" || { echo "Failed to cd to main repo dir $main_repo_dir" >&2; return 1; }
  fi
  local -a remove_args
  (( force )) && remove_args+=(--force)
  git worktree remove "${remove_args[@]}" "$target" || return 1
  echo "Removed worktree $target"
}
_rmwt() { _gwt }

compdef _gwt gwt
compdef _gwtpr gwtpr
compdef _rmwt rmwt
