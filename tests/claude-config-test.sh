#!/usr/bin/env bash
# shellcheck disable=SC2016
set -u
unset XDG_CONFIG_HOME XDG_STATE_HOME XDG_CACHE_HOME

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CLAUDE_DIR=$ROOT/claude
BASE_TMP=$(mktemp -d)
TMP=$BASE_TMP
CURRENT=""

usage() {
    cat <<'EOF'
Claude config test suite. Every test runs with HOME pointed at a temp folder.

  tests/claude-config-test.sh [test_name...]
EOF
}

fail() {
    echo "FAIL $CURRENT: $*"
    exit 1
}
assert_eq() { [ "$1" == "$2" ] || fail "$3 (expected '$1', got '$2')"; }
assert_contains() { case "$1" in *"$2"*) ;; *) fail "$3 (missing '$2' in '$1')" ;; esac }
assert_not_contains() { case "$1" in *"$2"*) fail "$3 (unexpected '$2' in '$1')" ;; esac }

installer() { source "$ROOT/bin/claude-setup"; }

test_link_creates() {
    "$ROOT/link" claude >/dev/null
    local f
    for f in CLAUDE.md rules/context7.md rules/working-style.md statusline-command.sh; do
        [ -L "$HOME/.claude/$f" ] || fail "$f is a symlink"
        assert_eq "$CLAUDE_DIR/$f" "$(readlink -f "$HOME/.claude/$f")" "$f points into the repo"
    done
    "$ROOT/link" --check claude >/dev/null || fail "link --check agrees"
}

test_backs_up_real_file() {
    mkdir -p "$HOME/.claude"
    echo old >"$HOME/.claude/CLAUDE.md"
    "$ROOT/link" claude >/dev/null || fail "links with a real file in the way"
    [ -L "$HOME/.claude/CLAUDE.md" ] || fail "replaced by a symlink"
    assert_eq old "$(cat "$HOME"/.claude/CLAUDE.md.bak-*)" "old file backed up"
}

test_backup_leaves_links_alone() {
    "$ROOT/link" claude >/dev/null
    "$ROOT/link" claude >/dev/null
    [ -L "$HOME/.claude/CLAUDE.md" ] || fail "links survive a re-run"
    assert_eq 0 "$(find "$HOME/.claude" -name '*.bak-*' | wc -l | tr -d ' ')" "no backups on re-run"
}

fixture_shared() {
    echo '{"model":"opus","permissions":{"ask":["Bash(git push*)"]},"autoMode":{"soft_deny":["$defaults","A"]}}' >"$TMP/shared.json"
}

test_merge_concat_automode() {
    installer
    fixture_shared
    echo '{"autoMode":{"soft_deny":["B","A"],"environment":["org: placeholder"]}}' >"$TMP/private.json"
    local out
    out=$(merge_settings "$TMP/shared.json" "$TMP/private.json")
    assert_eq '["$defaults","A","B"]' "$(jq -c .autoMode.soft_deny <<<"$out")" "arrays concatenated, deduped"
    assert_eq '["org: placeholder"]' "$(jq -c .autoMode.environment <<<"$out")" "private environment kept"
    assert_eq opus "$(jq -r .model <<<"$out")" "shared keys kept"
}

test_merge_keeps_both_sets_of_hooks() {
    installer
    echo '{"model":"opus","hooks":{"Stop":[{"hooks":[{"type":"command","command":"shared"}]}]}}' >"$TMP/shared.json"
    echo '{"model":"mine","hooks":{"Stop":[{"hooks":[{"type":"command","command":"private"}]}]}}' >"$TMP/private.json"
    local out
    out=$(merge_settings "$TMP/shared.json" "$TMP/private.json")
    assert_eq '["shared","private"]' "$(jq -c '[.hooks.Stop[].hooks[].command]' <<<"$out")" "hooks from both files run"
    assert_eq mine "$(jq -r .model <<<"$out")" "private value wins"
}

test_merge_no_private() {
    installer
    fixture_shared
    assert_eq "$(jq -S . "$TMP/shared.json")" "$(merge_settings "$TMP/shared.json" "$TMP/missing.json" | jq -S .)" "shared alone"
}

test_write_backs_up_local_change() {
    installer
    mkdir -p "$TMP/repo"
    fixture_shared
    cp "$TMP/shared.json" "$TMP/repo/settings.shared.json"
    write_settings "$TMP/repo" >/dev/null
    jq '.model = "x"' "$HOME/.claude/settings.json" >"$TMP/edited" && cat "$TMP/edited" >"$HOME/.claude/settings.json"
    local out
    out=$(write_settings "$TMP/repo")
    assert_contains "$out" "model" "differing key reported"
    assert_eq x "$(jq -r .model "$HOME"/.claude/settings.json.bak-*)" "local change backed up"
    assert_eq opus "$(jq -r .model "$HOME/.claude/settings.json")" "shared value written"
}

test_write_quiet_when_unchanged() {
    installer
    mkdir -p "$TMP/repo"
    fixture_shared
    cp "$TMP/shared.json" "$TMP/repo/settings.shared.json"
    write_settings "$TMP/repo" >/dev/null
    [ -f "$HOME/.claude/settings.json" ] || fail "settings.json written"
    assert_eq "" "$(write_settings "$TMP/repo")" "second write is silent"
    assert_eq 0 "$(find "$HOME/.claude" -name 'settings.json.bak-*' | wc -l | tr -d ' ')" "no backup"
}

test_first_run_keeps_existing_settings() {
    installer
    mkdir -p "$TMP/repo" "$HOME/.claude"
    echo '{"model":"opus","theme":"dark","hooks":{"Stop":[{"hooks":[{"type":"command","command":"shared"}]}]}}' >"$TMP/repo/settings.shared.json"
    echo '{"model":"mine","hooks":{"Stop":[{"hooks":[{"type":"command","command":"local"}]}]},"extra":1}' >"$HOME/.claude/settings.json"
    write_settings "$TMP/repo" >/dev/null
    local out=$HOME/.claude/settings.json
    assert_eq '{"extra":1,"hooks":{"Stop":[{"hooks":[{"command":"local","type":"command"}]}]},"model":"mine"}' \
        "$(jq -cS . "$HOME/.claude/settings.private.json")" "what only this machine had becomes private"
    assert_eq mine "$(jq -r .model "$out")" "this machine's value survives"
    assert_eq 1 "$(jq -r .extra "$out")" "this machine's extra key survives"
    assert_eq dark "$(jq -r .theme "$out")" "shared key added"
    assert_eq '["shared","local"]' "$(jq -c '[.hooks.Stop[].hooks[].command]' "$out")" "both hooks kept"
    assert_eq mine "$(jq -r .model "$HOME"/.claude/settings.json.bak-*)" "the old file is backed up"
}

test_split_roundtrip() {
    installer
    fixture_shared
    echo '{"model":"opus","permissions":{"ask":["Bash(git push*)"]},"autoMode":{"soft_deny":["$defaults","P1","A"],"environment":["org: placeholder"]}}' >"$TMP/current.json"
    split_private "$TMP/current.json" "$TMP/shared.json" >"$TMP/private.json"
    assert_eq '["P1"]' "$(jq -c .autoMode.soft_deny "$TMP/private.json")" "only extra soft_deny entries are private"
    assert_eq "$(sorted_json "$TMP/current.json")" "$(merge_settings "$TMP/shared.json" "$TMP/private.json" | sorted_json /dev/stdin)" "shared + private rebuilds current"
}

test_split_keeps_private_plugins() {
    installer
    fixture_shared
    echo '{"model":"opus","permissions":{"ask":["Bash(git push*)"]},"autoMode":{"soft_deny":["$defaults","A"]},"enabledPlugins":{"secret@mkt":true},"extraKnownMarketplaces":{"mkt":{"source":{"source":"github","repo":"o/r"}}}}' >"$TMP/current.json"
    split_private "$TMP/current.json" "$TMP/shared.json" >"$TMP/private.json"
    assert_eq true "$(jq '.enabledPlugins["secret@mkt"]' "$TMP/private.json")" "private plugin kept in private"
    assert_eq null "$(jq .model "$TMP/private.json")" "shared keys not duplicated"
    assert_eq "$(sorted_json "$TMP/current.json")" "$(merge_settings "$TMP/shared.json" "$TMP/private.json" | sorted_json /dev/stdin)" "rebuilds current"
}

test_shared_settings_point_at_linked_files() {
    local cmd
    while IFS= read -r cmd; do
        [ -x "$ROOT/bin/${cmd##*/}" ] || fail "hook command $cmd has no script in bin/"
    done < <(jq -r '[.hooks[][].hooks[].command | select(startswith("~/.local/bin/"))] | unique[]' "$CLAUDE_DIR/settings.shared.json")
    assert_eq "bash ~/.claude/statusline-command.sh" "$(jq -r .statusLine.command "$CLAUDE_DIR/settings.shared.json")" "status line command"
    [ -x "$CLAUDE_DIR/statusline-command.sh" ] || fail "status line script is in the claude package"
}

stub_cli() {
    mkdir -p "$TMP/bin"
    printf '#!/bin/sh\necho "%s $*" >>"%s"\n' "$1" "$TMP/calls" >"$TMP/bin/$1"
    chmod +x "$TMP/bin/$1"
}

fixture_merged_settings() {
    mkdir -p "$HOME/.claude"
    echo '{"enabledPlugins":{"a@m1":true,"b@m2":true,"off@m2":false},"extraKnownMarketplaces":{"m1":{"source":{"source":"github","repo":"o/m1"}},"m2":{"source":{"source":"github","repo":"o/m2"}}}}' >"$HOME/.claude/settings.json"
}

test_plugins_commands() {
    installer
    stub_cli claude
    fixture_merged_settings
    local out
    out=$(PATH=$TMP/bin:$PATH install_plugins <<<y)
    assert_contains "$out" "o/m1" "lists what it will fetch"
    assert_eq "claude plugin marketplace add o/m1|claude plugin marketplace add o/m2|claude plugin install a@m1 --scope user|claude plugin install b@m2 --scope user" \
        "$(paste -sd'|' "$TMP/calls")" "marketplaces then enabled plugins"
}

test_plugins_declined() {
    installer
    stub_cli claude
    fixture_merged_settings
    PATH=$TMP/bin:$PATH install_plugins <<<n >/dev/null
    [ -e "$TMP/calls" ] && fail "nothing fetched after a no"
    true
}

test_plugins_already_installed_is_silent() {
    installer
    stub_cli claude
    fixture_merged_settings
    mkdir -p "$HOME/.claude/plugins"
    echo '{"m1":{},"m2":{}}' >"$HOME/.claude/plugins/known_marketplaces.json"
    echo '{"plugins":{"a@m1":[],"b@m2":[]}}' >"$HOME/.claude/plugins/installed_plugins.json"
    assert_eq "" "$(PATH=$TMP/bin:$PATH install_plugins </dev/null)" "no prompt when everything is installed"
    [ -e "$TMP/calls" ] && fail "nothing fetched"
    true
}

test_plugins_missing_cli() {
    installer
    fixture_merged_settings
    mkdir -p "$TMP/tools"
    ln -s "$(command -v jq)" "$TMP/tools/jq"
    local out
    out=$(PATH=$TMP/tools install_plugins) || fail "missing claude CLI is not an error"
    assert_contains "$out" "claude CLI not found" "hint printed"
}

test_skills_commands() {
    installer
    stub_cli npx
    PATH=$TMP/bin:$PATH install_skills "$CLAUDE_DIR" >/dev/null
    assert_eq "$(grep -c . "$CLAUDE_DIR/skills.txt")" "$(grep -c '^npx -y skills add .* -g -y --skill \*$' "$TMP/calls")" "one skills add per source"
}

plant_repo() {
    git init -q "$TMP/repo"
    printf '%s\n' "$1" >"$TMP/repo/notes.txt"
}

test_privacy_clean() {
    "$ROOT/.githooks/privacy-check" "$ROOT" || fail "the real repo passes the built-in checks"
}

test_privacy_term() {
    mkdir -p "$HOME/.claude"
    echo zebracorp >"$HOME/.claude/private-terms.txt"
    plant_repo "client is $(printf 'Zebra%s' Corp)"
    local out
    out=$("$ROOT/.githooks/privacy-check" "$TMP/repo") && fail "planted term must fail"
    assert_contains "$out" "notes.txt" "offending file reported"
}

test_privacy_email() {
    plant_repo "contact $(printf '%s@%s' a b.co)"
    local out
    out=$("$ROOT/.githooks/privacy-check" "$TMP/repo") && fail "planted email must fail"
    assert_contains "$out" "notes.txt" "offending file reported"
}

test_link_replaces_old_installer_links() {
    mkdir -p "$HOME/.config" "$HOME/.local/bin"
    ln -s "$ROOT/kitty" "$HOME/.config/kitty"
    ln -s "$ROOT/scripts/t" "$HOME/.local/bin/t"
    ln -s "$ROOT/bin/theme" "$HOME/.local/bin/theme"
    echo mine >"$HOME/.local/bin/unrelated"
    "$ROOT/link" kitty bin >/dev/null || fail "links over the old installer's links"
    [ ! -L "$HOME/.config/kitty" ] || fail "whole-folder link replaced by a real folder"
    [ -f "$ROOT/kitty/kitty.conf" ] || fail "the repo's own files survive"
    assert_eq "$ROOT/kitty/kitty.conf" "$(readlink -f "$HOME/.config/kitty/kitty.conf")" "kitty.conf linked on its own"
    assert_eq "$ROOT/bin/t" "$(readlink -f "$HOME/.local/bin/t")" "dangling link repointed"
    assert_eq mine "$(cat "$HOME/.local/bin/unrelated")" "files outside the package untouched"
    assert_eq 0 "$(find "$HOME" -name '*.bak-*' | wc -l | tr -d ' ')" "old links are not backed up"
    "$ROOT/link" --check kitty bin >/dev/null || fail "link --check agrees"
}

sorted_json() { jq -S 'if .autoMode then .autoMode |= with_entries(if (.value | type) == "array" then .value |= sort else . end) else . end' "$1"; }

trap 'rm -rf "$BASE_TMP"' EXIT

case ${1:-} in -h | --help) usage && exit 0 ;; esac
names=("$@")
if [ ${#names[@]} -eq 0 ]; then
    while read -r name; do names+=("$name"); done < <(declare -F | awk '{print $3}' | grep '^test_')
fi
failed=0
for CURRENT in "${names[@]}"; do
    TMP=$BASE_TMP/$CURRENT && mkdir -p "$TMP/home"
    if (HOME=$TMP/home && export HOME && "$CURRENT"); then echo "PASS $CURRENT"; else failed=$((failed + 1)); fi
done
echo "---- ${#names[@]} run, $failed failed"
[ "$failed" -eq 0 ]
