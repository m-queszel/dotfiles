#!/usr/bin/env bash
# Portable Claude config test suite. Every test runs with HOME pointed at a temp folder.
# Usage: bash scripts/tests/claude-config-test.sh [test_name...]
set -u

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
CLAUDE_DIR=$ROOT/claude
BASE_TMP=$(mktemp -d)
TMP=$BASE_TMP
CURRENT=""

fail() { echo "FAIL $CURRENT: $*"; exit 1; }
assert_eq() { [ "$1" == "$2" ] || fail "$3 (expected '$1', got '$2')"; }
assert_contains() { case "$1" in *"$2"*) ;; *) fail "$3 (missing '$2' in '$1')" ;; esac; }
assert_not_contains() { case "$1" in *"$2"*) fail "$3 (unexpected '$2' in '$1')" ;; esac; }

installer() { source "$CLAUDE_DIR/install-claude"; }

test_link_creates() {
    installer
    link_files "$CLAUDE_DIR" >/dev/null
    local f
    for f in CLAUDE.md rules/context7.md rules/working-style.md commands/commit-message.md statusline-command.sh; do
        [ -L "$HOME/.claude/$f" ] || fail "$f is a symlink"
        assert_eq "$CLAUDE_DIR/$f" "$(readlink "$HOME/.claude/$f")" "$f points into the repo"
    done
}

test_link_backs_up_real_file() {
    installer
    mkdir -p "$HOME/.claude"
    echo old >"$HOME/.claude/CLAUDE.md"
    link_files "$CLAUDE_DIR" >/dev/null
    [ -L "$HOME/.claude/CLAUDE.md" ] || fail "replaced by a symlink"
    assert_eq old "$(cat "$HOME"/.claude/CLAUDE.md.bak-*)" "old file backed up"
}

test_link_idempotent() {
    installer
    link_files "$CLAUDE_DIR" >/dev/null
    link_files "$CLAUDE_DIR" >/dev/null
    [ -L "$HOME/.claude/CLAUDE.md" ] || fail "links exist after re-run"
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

test_skills_list_has_no_unused_pack() {
    assert_not_contains "$(cat "$CLAUDE_DIR/skills.txt")" "Cybersecurity-Skills" "unused 818-skill pack dropped"
}

test_plugins_missing_cli() {
    installer
    fixture_merged_settings
    local out
    out=$(PATH=/usr/bin:/bin install_plugins) || fail "missing claude CLI is not an error"
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
    cp -R "$CLAUDE_DIR" "$TMP/repo/claude"
    printf '%s\n' "$1" >"$TMP/repo/notes.txt"
}

test_privacy_clean() {
    "$CLAUDE_DIR/privacy-check" "$ROOT" >/dev/null || fail "the real repo passes the built-in checks"
}

test_privacy_term() {
    mkdir -p "$HOME/.claude"
    echo zebracorp >"$HOME/.claude/private-terms.txt"
    plant_repo "client is $(printf 'Zebra%s' Corp)"
    local out
    out=$("$CLAUDE_DIR/privacy-check" "$TMP/repo") && fail "planted term must fail"
    assert_contains "$out" "notes.txt" "offending file reported"
}

test_privacy_email() {
    plant_repo "contact $(printf '%s@%s' a b.co)"
    local out
    out=$("$CLAUDE_DIR/privacy-check" "$TMP/repo") && fail "planted email must fail"
    assert_contains "$out" "notes.txt" "offending file reported"
}

test_install_stops_on_leak() {
    mkdir -p "$HOME/.claude"
    echo zebracorp >"$HOME/.claude/private-terms.txt"
    plant_repo "$(printf 'Zebra%s' Corp)"
    "$TMP/repo/claude/install-claude" >/dev/null 2>&1 && fail "install must stop on a leak"
    [ -e "$HOME/.claude/settings.json" ] && fail "nothing written before the check passes"
    true
}

sorted_json() { jq -S 'if .autoMode then .autoMode |= with_entries(if (.value | type) == "array" then .value |= sort else . end) else . end' "$1"; }

trap 'rm -rf "$BASE_TMP"' EXIT

names=("$@")
[ ${#names[@]} -gt 0 ] || names=($(declare -F | awk '{print $3}' | grep '^test_'))
failed=0
for CURRENT in "${names[@]}"; do
    TMP=$BASE_TMP/$CURRENT && mkdir -p "$TMP/home"
    if (HOME=$TMP/home && export HOME && "$CURRENT"); then echo "PASS $CURRENT"; else failed=$((failed + 1)); fi
done
echo "---- ${#names[@]} run, $failed failed"
[ "$failed" -eq 0 ]
