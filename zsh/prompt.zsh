autoload -Uz colors && colors
setopt PROMPT_SUBST

git_prompt_info() {
  local ref
  ref=$(git symbolic-ref HEAD 2> /dev/null) || \
  ref=$(git rev-parse --short HEAD 2> /dev/null) || return 0

  local dirty=""
  if ! git diff --quiet 2> /dev/null || ! git diff --cached --quiet 2> /dev/null; then
    dirty="%F{214}*%f"
  fi

  echo " %F{75}(%F{78}${ref#refs/heads/}${dirty}%F{75})%f"
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
%F{32}%~\$(git_prompt_info) %F{105}%(!.#.>)%f "
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
