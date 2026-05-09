#!/usr/bin/env bash
input=$(cat)
model=$(echo "$input" | jq -r '.model.display_name // .model.id // "unknown"' | sed 's/ (1M context)//')
cwd=$(echo "$input" | jq -r '.cwd // .workspace.current_dir // "unknown"' | sed "s|/Users/danbjorge|~|")
used=$(echo "$input" | jq -r '
  if .context_window.current_usage == null then empty
  else (
    (.context_window.current_usage.input_tokens // 0) +
    (.context_window.current_usage.cache_creation_input_tokens // 0) +
    (.context_window.current_usage.cache_read_input_tokens // 0)
  ) | tostring
  end')
total=$(echo "$input" | jq -r '.context_window.context_window_size // empty')

format_tokens() {
  local n=$1
  # Route to M branch if n rounds to >=1M (i.e. n >= 950000)
  if [ "$n" -ge 950000 ]; then
    # tenths_of_M = round(n / 100000)
    local tenths_of_M
    tenths_of_M=$(echo "($n + 50000) / 100000" | bc)
    if [ "$tenths_of_M" -ge 100 ]; then
      # >= 10M: output whole number rounded from tenths
      local whole
      whole=$(echo "($tenths_of_M + 5) / 10" | bc)
      printf "%dM" "$whole"
    elif [ "$((tenths_of_M % 10))" -eq 0 ]; then
      # No fractional part needed
      printf "%dM" "$((tenths_of_M / 10))"
    else
      printf "%d.%dM" "$((tenths_of_M / 10))" "$((tenths_of_M % 10))"
    fi
  elif [ "$n" -ge 1000 ]; then
    # tenths_of_k = round(n / 100)
    local tenths_of_k
    tenths_of_k=$(echo "($n + 50) / 100" | bc)
    if [ "$tenths_of_k" -ge 100 ]; then
      # >= 10k: output whole number rounded from tenths
      local whole
      whole=$(echo "($tenths_of_k + 5) / 10" | bc)
      printf "%dk" "$whole"
    elif [ "$((tenths_of_k % 10))" -eq 0 ]; then
      # No fractional part needed
      printf "%dk" "$((tenths_of_k / 10))"
    else
      printf "%d.%dk" "$((tenths_of_k / 10))" "$((tenths_of_k % 10))"
    fi
  else
    printf "%s" "$n"
  fi
}

if [ -n "$used" ] && [ -n "$total" ]; then
  used_fmt=$(format_tokens "$used")
  total_fmt=$(format_tokens "$total")
  smart_threshold=$(( total * 40 / 100 < 100000 ? total * 40 / 100 : 100000 ))
  warning_threshold=$(( total * 60 / 100 < 200000 ? total * 60 / 100 : 200000 ))
  if [ "$used" -lt "$smart_threshold" ]; then
    color='\033[38;5;108m'
  elif [ "$used" -lt "$warning_threshold" ]; then
    color='\033[38;5;179m'
  else
    color='\033[38;5;167m'
  fi
  printf "%b%s\033[0m/%s  %s  %s" "$color" "$used_fmt" "$total_fmt" "$cwd" "$model"
else
  printf "%s  %s" "$cwd" "$model"
fi
