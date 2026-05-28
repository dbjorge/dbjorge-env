# PREREQUISITES:
#   - git
#   - gh
#   - vim
# OPTIONAL PREREQS:
#   - asdf (or nvm)
#   - rbenv
#   - uv
#   - openjdk
#   - ~/chromedriver
#   - cargo
#   - cursor
#   - code
#   - zsh-syntax-highlighting
#   - zsh-history-substring-search
#   - zsh-completions
#   - git clone https://github.com/zsh-users/zsh-history-substring-search ~/repos/zsh-history-substring-search
#   - git clone https://github.com/zsh-users/zsh-history-substring-search ~/repos/zsh-history-substring-search

# INSTALLATION:
# Use install-zsh.sh, or, ensure ~/.zshrc starts with:
# 
# source $HOME/repos/dbjorge-env/.zshrc

## --- Tool setup

# fnm
if [ -f "$(which fnm)" ]; then
  eval "$(fnm env --use-on-cd --shell zsh)"
#nvm (deprecated, prefer fnm)
elif [ -d "$HOME/.nvm" ]; then
  echo "Using nvm"
  export NVM_DIR="$HOME/.nvm"
  [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
  [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion" 
fi

# rbenv
if [ -d "$HOME/.rbenv" ]; then
  export PATH="$HOME/.rbenv/bin:$PATH"
  eval "$(rbenv init -)"
fi

# openjdk
if [ -d "/opt/homebrew/opt/openjdk" ]; then
  export PATH="/opt/homebrew/opt/openjdk/bin:$PATH"
fi

alias ssh="TERM=xterm-256color ssh"

export GH_PAGER="cat"
export PATH="$HOME/chromedriver:$HOME/.cargo/bin:$PATH:$HOME/repos/dbjorge-env/scripts"
export AWS_SDK_LOAD_CONFIG=1

# Preferred editor for local and remote sessions
if [[ -n $SSH_CONNECTION ]]; then
  export EDITOR='vim'
else
  if command -v cursor > /dev/null; then
    export EDITOR='cursor'
  elif command -v code > /dev/null; then
    export EDITOR='code'
  else
    export EDITOR='vim'
  fi
fi
export VISUAL="$EDITOR"

# Disables line number gutter in bat for easier copy/paste
export BAT_STYLE=header-filename,header-filesize,grid

## --- Directory management

# Inspired by https://thevaluable.dev/zsh-install-configure-mouseless/
setopt AUTO_PUSHD           # Push the current directory visited on the stack.
setopt PUSHD_IGNORE_DUPS    # Do not store duplicates in the stack.
setopt PUSHD_SILENT         # Do not print the directory stack after pushd or popd.
alias d='dirs -v'
for index ({1..9}) alias "$index"="cd +${index}"; unset index

## --- zsh options

setopt COMPLETE_IN_WORD
bindkey  "^[[H"   beginning-of-line
bindkey  "^[[F"   end-of-line
bindkey  "^[[3~"  delete-char

## --- Prompt

source "${0:A:h}/zsh/prompt.zsh"

## --- Plugins

ZSH_HISTORY_SUBSTRING_SEARCH_PATH=~/repos/zsh-history-substring-search/zsh-history-substring-search.zsh
if [ -f $ZSH_HISTORY_SUBSTRING_SEARCH_PATH ]; then
  source $ZSH_HISTORY_SUBSTRING_SEARCH_PATH
  bindkey '^[[A' history-substring-search-up
  bindkey '^[[B' history-substring-search-down
fi

# Must load last
for ZSH_SYNTAX_HIGHLIGHTING_PATH in \
  "/opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" \
  "/usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"; do
  if [ -f $ZSH_SYNTAX_HIGHLIGHTING_PATH ]; then
    source $ZSH_SYNTAX_HIGHLIGHTING_PATH
    break
  fi
done
ZSH_HIGHLIGHT_HIGHLIGHTERS+=(brackets)

## --- Aliases

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
      local i
      for i in {1..${#wts[@]}}; do
        echo "  $i) ${wts[$i]}"
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
# bare `rmwt` shows a numbered picker. Refuses if dirty or has unpushed commits
# (no upstream counts as unpushed) unless --force/-f is passed.
rmwt() {
  local force=0
  if [[ "$1" == "--force" || "$1" == "-f" ]]; then force=1; shift; fi
  local root repo parent wt_dir
  root=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "Not in a git repo" >&2; return 1; }
  repo=$(basename "$root")
  parent=$(dirname "$root")
  if [[ "$(basename "$parent")" != "repos" ]]; then
    echo "Error: must run from main repo (~/repos/<repo>)" >&2; return 1
  fi
  wt_dir="$parent/../worktrees/$repo"
  local name
  if [[ $# -eq 0 ]]; then
    if [[ ! -d "$wt_dir" ]] || [[ -z "$(ls -A "$wt_dir" 2>/dev/null)" ]]; then
      echo "No worktrees found for $repo" >&2; return 1
    fi
    local -a wts
    wts=("$wt_dir"/*(/:t))
    echo "Available worktrees for $repo:"
    local i
    for i in {1..${#wts[@]}}; do
      echo "  $i) ${wts[$i]}"
    done
    local choice
    echo -n "Select worktree to remove: "
    read choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#wts[@]} )); then
      name="${wts[$choice]}"
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
  local -a remove_args
  (( force )) && remove_args+=(--force)
  git worktree remove "${remove_args[@]}" "$target" || return 1
  echo "Removed worktree $target"
}
_rmwt() { _gwt }

alias cdr="cd ~/repos/"
alias cdac="cd ~/repos/axe-core"
alias cdacnpm="cd ~/repos/axe-core-npm"
alias cdacnuget="cd ~/repos/axe-core-nuget"
alias cdenv="cd ~/repos/dbjorge-env"
alias cdw3="cd ~/repos/wcag"
alias cdwcag="cd ~/repos/wcag"
alias cdwe="cd ~/repos/watcher-examples"
alias cdwec="cd ~/repos/watcher-examples/cypress/basic"
alias cdwep="cd ~/repos/watcher-examples/playwright/basic"

autoload -U compinit
compinit
compdef _gwt gwt
compdef _gwtpr gwtpr
compdef _rmwt rmwt
