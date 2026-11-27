#!/bin/bash

input=$(cat)
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd')

if [[ "$cwd" == "$HOME"* ]]; then
    display_path="~${cwd#$HOME}"
else
    display_path="$cwd"
fi

IFS='/' read -ra raw_parts <<< "$display_path"
n=${#raw_parts[@]}
parts=()
for ((i = 0; i < n; i++)); do
    p="${raw_parts[$i]}"
    if [[ $i -eq $((n - 1)) || -z "$p" || "$p" == "~" ]]; then
        parts+=("$p")
    else
        parts+=("${p:0:1}")
    fi
done
short_path=$(IFS=/; echo "${parts[*]}")

user=$(whoami)
host=$(hostname)

RED='\033[31m'
RESET='\033[0m'

printf "${RED}%s${RESET}@%s ${RED}%s${RESET}" "$user" "$host" "$short_path"

# Git branch and context-window usage, each dropped when unknown
branch=$(git -C "$cwd" branch --show-current 2>/dev/null)
ctx=$(echo "$input" | jq -r '.context_window.used_percentage // empty | round')
[ -n "$branch" ] && printf " %s" "$branch"
[ -n "$ctx" ] && printf " · %s%% ctx" "$ctx"
true
