# dbjorge.zsh-theme
#
# Author: Dan Bjorge

PS1_SUFFIX="
${FG[032]}%~\$(git_prompt_info)\$(hg_prompt_info) ${FG[105]}%(!.#.>)%{$reset_color%} "
PS2="%{$fg[red]%}\ %{$reset_color%}"

function preexec() {
  timer=$(($(gdate +%s%0N)/1000000))
}

function precmd() {
  export PS1="$PS1_SUFFIX"

  if [ $timer ]; then
    now=$(($(gdate +%s%0N)/1000000))
    elapsed=$(($now-$timer))
    unset timer

    EXIT_CODE_PART="%(?.%F{green}✔.%F{red}%? ✘)%{$reset_color%}"
    ELAPSED_PART="%F{cyan}${elapsed}ms%{$reset_color%}"
    export PS1="$EXIT_CODE_PART $ELAPSED_PART$PS1_SUFFIX"
  else
    
  fi
}

# git settings
ZSH_THEME_GIT_PROMPT_PREFIX=" ${FG[075]}(${FG[078]}"
ZSH_THEME_GIT_PROMPT_CLEAN=""
ZSH_THEME_GIT_PROMPT_DIRTY="${FG[214]}*%{$reset_color%}"
ZSH_THEME_GIT_PROMPT_SUFFIX="${FG[075]})%{$reset_color%}"

# hg settings
ZSH_THEME_HG_PROMPT_PREFIX=" ${FG[075]}(${FG[078]}"
ZSH_THEME_HG_PROMPT_CLEAN=""
ZSH_THEME_HG_PROMPT_DIRTY="${FG[214]}*%{$reset_color%}"
ZSH_THEME_HG_PROMPT_SUFFIX="${FG[075]})%{$reset_color%}"

# virtualenv settings
ZSH_THEME_VIRTUALENV_PREFIX=" ${FG[075]}["
ZSH_THEME_VIRTUALENV_SUFFIX="]%{$reset_color%}"