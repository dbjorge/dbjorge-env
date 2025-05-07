# PREREQUISITES:
# - brew install git gh
# - https://ohmyz.sh/#install

## --- Oh My Zsh config

export ZSH="$HOME/.oh-my-zsh"

# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
ZSH_CUSTOM="$HOME/repos/dbjorge-env/.oh-my-zsh/custom"
ZSH_THEME="dbjorge"

# oh-my-zsh update policy 
zstyle ':omz:update' mode reminder
zstyle ':omz:update' frequency 13 # days

# Plugins:
# Standard plugins can be found in $ZSH/plugins/
# Custom plugins may be added to $ZSH_CUSTOM/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(git poetry history-substring-search)
# history-substring-search bindings
bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down

source $ZSH/oh-my-zsh.sh

## --- Tool setup

# nvm
if [ -d "$HOME/.nvm" ]; then
  export NVM_DIR="$HOME/.nvm"
  [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" # This loads nvm
fi

if [ -d "$HOME/.rbenv" ]; then
  export PATH="$HOME/.rbenv/bin:$PATH"
  eval "$(rbenv init -)"
fi

if [ -d "/opt/homebrew/opt/openjdk" ]; then
  export PATH="/opt/homebrew/opt/openjdk/bin:$PATH"
fi

alias ssh="TERM=xterm-256color ssh"

export GH_PAGER="cat"
export PATH="$HOME/chromedriver:$PATH"

export AWS_SDK_LOAD_CONFIG=1

# Preferred editor for local and remote sessions
if [[ -n $SSH_CONNECTION ]]; then
  export EDITOR='vim'
else
  export EDITOR='code'
fi

eval "$(gh copilot alias -- zsh)"

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
