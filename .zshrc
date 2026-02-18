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
  echo "Using fnm"
  eval "$(fnm env --use-on-cd --shell zsh)"
  alias nvm="echo 'Use asdf instead' && exit 1"
#nvm (deprecated, prefer asdf)
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
