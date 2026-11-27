#!/usr/bin/env bash

input=$(cat)
cwd=$(jq -r '.workspace.current_dir // .cwd' <<<"$input")

if [[ $cwd == "$HOME"* ]]; then
    display_path="~${cwd#"$HOME"}"
else
    display_path=$cwd
fi

IFS='/' read -ra raw_parts <<<"$display_path"
n=${#raw_parts[@]}
parts=()
for ((i = 0; i < n; i++)); do
    p=${raw_parts[$i]}
    if [[ $i -eq $((n - 1)) || -z $p || $p == "~" ]]; then
        parts+=("$p")
    else
        parts+=("${p:0:1}")
    fi
done
short_path=$(IFS=/ && echo "${parts[*]}")

red=$'\033[31m' reset=$'\033[0m'
printf '%s%s%s@%s %s%s%s' "$red" "$USER" "$reset" "$HOSTNAME" "$red" "$short_path" "$reset"

branch=$(git -C "$cwd" branch --show-current 2>/dev/null)
ctx=$(jq -r '.context_window.used_percentage // empty | round' <<<"$input")
[ -n "$branch" ] && printf ' %s' "$branch"
[ -n "$ctx" ] && printf ' · %s%% ctx' "$ctx"
true
