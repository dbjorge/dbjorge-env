# PREREQUISITES:
#   - git
#   - gh
#   - vim
# OPTIONAL PREREQS:
#   - nvm
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

# nvm
if [ -d "$HOME/.nvm" ]; then
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
ZSH_SYNTAX_HIGHLIGHTING_PATH=/usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
if [ -f $ZSH_SYNTAX_HIGHLIGHTING_PATH ]; then
  source $ZSH_SYNTAX_HIGHLIGHTING_PATH
  ZSH_HIGHLIGHT_HIGHLIGHTERS+=(brackets)
fi

## --- Aliases

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
