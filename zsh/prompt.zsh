autoload -Uz colors && colors
setopt PROMPT_SUBST

_is_in_named_worktree() {
  local gitdir branch="$1"
  gitdir=$(git rev-parse --absolute-git-dir 2>/dev/null) || return 1
  [[ "$gitdir" == *"/worktrees/"* ]] || return 1
  [[ "$(basename "$(git rev-parse --show-toplevel 2>/dev/null)")" == "$branch" ]]
}

# Combined path + git info prompt segment. Runs the worktree detection once
# and uses the result for both the path highlighting and branch display.
prompt_git_segment() {
  local path_str
  path_str=$(print -P '%~')

  local ref branch
  ref=$(git symbolic-ref HEAD 2>/dev/null) || ref=$(git rev-parse --short HEAD 2>/dev/null)
  if [[ -z "$ref" ]]; then
    echo "${path_str}"
    return
  fi

  branch="${ref#refs/heads/}"

  local dirty=""
  git diff --quiet 2>/dev/null || dirty=1
  git diff --cached --quiet 2>/dev/null || dirty=1
  if [[ -n "$dirty" ]]; then
    dirty="%F{214}*%f"
  fi

  if _is_in_named_worktree "$branch"; then
    # Highlight the branch/worktree name in the path; omit the separate branch indicator
    path_str="${path_str/$branch/%F{78\}${branch}%F{32\}}"
    echo "${path_str}${dirty}"
  else
    echo "${path_str} %F{75}(%F{78}${branch}${dirty}%F{75})%f"
  fi
}

timestamp() {
  if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS: use gdate (GNU date from Homebrew)
    echo $(($(gdate +%s%0N)/1000000))
  else
    # Linux/RHEL: use standard date
    echo $(($(date +%s%N)/1000000))
  fi
}

PS1_SUFFIX="
%F{32}\$(prompt_git_segment) %F{105}%(!.#.>)%f "
PS2="%F{red}\ %f"

function preexec() {
  timer=$(timestamp)
}

function precmd() {
  export PS1="$PS1_SUFFIX"

  if [ $timer ]; then
    now=$(timestamp)
    elapsed=$(($now-$timer))
    unset timer

    EXIT_CODE_PART="%(?.%F{green}✔.%F{red}%? ✘)%f"
    ELAPSED_PART="%F{cyan}${elapsed}ms%f"
    export PS1="$EXIT_CODE_PART $ELAPSED_PART$PS1_SUFFIX"
  fi
}
