#!/usr/bin/env bash
# Claude cockpit test suite.
# Every test runs against a scratch tmux server, never the live one.
# Usage: bash scripts/tests/cockpit-test.sh [test_name...]
set -u

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
SCRIPTS=$ROOT/scripts
LIVE_SOCKET=/private/tmp/tmux-$(id -u)/default
SOCK=${TMUX_TMPDIR:-/tmp}/tmux-$(id -u)/cockpit-test
BASE_TMP=$(mktemp -d)
TMP=$BASE_TMP
CURRENT=""

export TMUX="$SOCK,0,0"
unset TMUX_PANE

start_server() {
    stop_server
    tmux -S "$SOCK" -f "${1:-/dev/null}" new-session -d -s t -x 200 -y 50 || return 1
    export TMUX="$(tmux -S "$SOCK" display -p '#{socket_path}'),0,0"
}

stop_server() {
    local s=${TMUX%%,*} i
    tmux -S "$SOCK" kill-server 2>/dev/null
    export TMUX="$SOCK,0,0"
    for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
        pulses "$s" >/dev/null || break
        sleep 0.1
    done
    true
}

pulses() {
    local pids p found=1
    pids=$(pgrep -f "claude-tmux-pulse $1") || return 1
    for p in $pids; do
        echo "$pids" | grep -qx "$(ps -o ppid= -p "$p" | tr -d ' ')" && continue
        echo "$p"
        found=0
    done
    return $found
}

agent_pane() { tmux new-window -d -t t: -P -F '#{pane_id}' 'sleep 600'; }

opt() { tmux show -pqv -t "$1" "$2" 2>/dev/null; }

fail() { echo "FAIL $CURRENT: $*"; exit 1; }
assert_eq() { [ "$1" == "$2" ] || fail "$3 (expected '$1', got '$2')"; }
assert_contains() { case "$1" in *"$2"*) ;; *) fail "$3 (missing '$2' in '$1')" ;; esac; }
assert_not_contains() { case "$1" in *"$2"*) fail "$3 (unexpected '$2' in '$1')" ;; esac; }


test_harness_isolated() {
    start_server
    local s
    s=$(tmux display -p '#{socket_path}')
    assert_contains "$s" "/cockpit-test" "scratch socket in use"
    [ "$s" != "$LIVE_SOCKET" ] || fail "test reached the live tmux server"
}

test_housekeeping() {
    start_server "$ROOT/tmux/tmux.conf"
    assert_eq "on" "$(tmux show -gv allow-passthrough)" "allow-passthrough"
    assert_eq "on" "$(tmux show -sv extended-keys)" "extended-keys"
    assert_eq "heavy" "$(tmux show -gv pane-border-lines)" "pane-border-lines"
    assert_contains "$(tmux list-keys -T prefix y)" "pbcopy" "prefix+y uses pbcopy"
    assert_not_contains "$(tmux list-keys -T prefix D)" "jessarcher" "prefix+D removed"
    local e
    e=$(tmux list-keys -T prefix e)
    assert_contains "$e" "new-window" "prefix+e opens a window"
    assert_contains "$e" "-n nvim" "prefix+e names it nvim"
}


hook() {
    printf '%s' "$2" | TMUX_PANE=$1 COCKPIT_NOTIFY_LOG=$TMP/notify.log "$SCRIPTS/claude-tmux-hook"
}

test_hook_states() {
    start_server
    local p
    p=$(agent_pane)
    hook "$p" '{"hook_event_name":"SessionStart","cwd":"/tmp"}'
    assert_eq idle "$(opt "$p" @claude_state)" "SessionStart"
    hook "$p" '{"hook_event_name":"UserPromptSubmit"}'
    assert_eq working "$(opt "$p" @claude_state)" "UserPromptSubmit"
    hook "$p" '{"hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"ls"}}'
    assert_eq waiting "$(opt "$p" @claude_state)" "PermissionRequest"
    assert_eq 1 "$(opt "$p" @claude_attn)" "PermissionRequest attn"
    hook "$p" '{"hook_event_name":"PostToolUse","tool_name":"Bash"}'
    assert_eq working "$(opt "$p" @claude_state)" "PostToolUse"
    assert_eq "" "$(opt "$p" @claude_attn)" "PostToolUse clears attn"
    hook "$p" '{"hook_event_name":"PreToolUse","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Which?"}]}}'
    assert_eq waiting "$(opt "$p" @claude_state)" "PreToolUse AskUserQuestion"
    hook "$p" '{"hook_event_name":"PostToolUseFailure","tool_name":"AskUserQuestion"}'
    assert_eq working "$(opt "$p" @claude_state)" "PostToolUseFailure"
    hook "$p" '{"hook_event_name":"Notification","notification_type":"elicitation_dialog","message":"Pick one"}'
    assert_eq waiting "$(opt "$p" @claude_state)" "Notification elicitation_dialog"
    hook "$p" '{"hook_event_name":"StopFailure"}'
    assert_eq waiting "$(opt "$p" @claude_state)" "StopFailure"
    hook "$p" '{"hook_event_name":"Stop","last_assistant_message":"All done"}'
    assert_eq done "$(opt "$p" @claude_state)" "Stop"
    assert_eq 1 "$(opt "$p" @claude_attn)" "Stop attn"
    [ -n "$(opt "$p" @claude_ts)" ] || fail "Stop sets @claude_ts"
    hook "$p" '{"hook_event_name":"SubagentStop"}'
    assert_eq done "$(opt "$p" @claude_state)" "SubagentStop ignored"
    hook "$p" '{"hook_event_name":"SessionEnd"}'
    assert_eq "" "$(opt "$p" @claude_state)" "SessionEnd clears state"
    assert_eq "" "$(tmux show -pv -t "$p" pane-border-style 2>/dev/null)" "SessionEnd restores border"
}

test_hook_label() {
    start_server
    local p1 p2 p3
    git init -q -b AB-1-x "$TMP/repo"
    mkdir -p "$TMP/foo-bar"
    p1=$(agent_pane) p2=$(agent_pane) p3=$(agent_pane)
    hook "$p1" '{"hook_event_name":"SessionStart","cwd":"'"$TMP/repo"'"}'
    assert_eq "AB-1-x" "$(opt "$p1" @claude_label)" "branch label"
    hook "$p2" '{"hook_event_name":"SessionStart","cwd":"'"$TMP/repo"'"}'
    assert_eq "AB-1-x #2" "$(opt "$p2" @claude_label)" "duplicate label numbered"
    hook "$p1" '{"hook_event_name":"SessionStart","cwd":"'"$TMP/repo"'"}'
    assert_eq "AB-1-x" "$(opt "$p1" @claude_label)" "restart keeps own label"
    hook "$p3" '{"hook_event_name":"SessionStart","cwd":"'"$TMP/foo-bar"'"}'
    assert_eq "foo-bar" "$(opt "$p3" @claude_label)" "folder label"
}

test_hook_focus() {
    start_server
    local p
    p=$(agent_pane)
    hook "$p" '{"hook_event_name":"PermissionRequest","tool_name":"Bash"}'
    "$SCRIPTS/claude-tmux-hook" focus-in "$p"
    assert_eq "" "$(opt "$p" @claude_attn)" "focus-in clears attn"
    assert_eq waiting "$(opt "$p" @claude_state)" "focus-in keeps state"
    "$SCRIPTS/claude-tmux-hook" focus-out "$p" ""
    assert_eq waiting "$(opt "$p" @claude_state)" "app switch keeps waiting"
    "$SCRIPTS/claude-tmux-hook" focus-out "$p" "attached,focused"
    assert_eq working "$(opt "$p" @claude_state)" "leaving pane counts as answered"
    hook "$p" '{"hook_event_name":"Stop"}'
    "$SCRIPTS/claude-tmux-hook" focus-out "$p" "attached,focused"
    assert_eq done "$(opt "$p" @claude_state)" "focus-out leaves done alone"
}

test_hook_outside_tmux() {
    local out
    out=$(env -u TMUX -u TMUX_PANE "$SCRIPTS/claude-tmux-hook" <<<'{"hook_event_name":"Stop"}' 2>&1) ||
        fail "non-zero exit outside tmux"
    assert_eq "" "$out" "silent outside tmux"
    out=$(hook %999 '{"hook_event_name":"Stop"}' 2>&1) || fail "non-zero exit with dead server"
    assert_eq "" "$out" "silent with dead server"
}


log_lines() { [ -f "$TMP/notify.log" ] && wc -l <"$TMP/notify.log" | tr -d ' ' || echo 0; }
last_log() { tail -1 "$TMP/notify.log"; }

test_notify_bodies() {
    start_server
    local p tab=$'\t' n long msg
    git init -q -b AB-9-y "$TMP/repo2"
    p=$(agent_pane)
    hook "$p" '{"hook_event_name":"SessionStart","cwd":"'"$TMP/repo2"'"}'
    hook "$p" '{"hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"php artisan test"}}'
    assert_eq "Claude · AB-9-y${tab}Bash: php artisan test" "$(last_log)" "permission body"
    hook "$p" '{"hook_event_name":"PreToolUse","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Which DB?"}]}}'
    assert_eq "Claude · AB-9-y${tab}Which DB?" "$(last_log)" "question body"
    hook "$p" '{"hook_event_name":"Notification","notification_type":"elicitation_dialog","message":"Pick one"}'
    assert_eq "Claude · AB-9-y${tab}Pick one" "$(last_log)" "elicitation body"
    hook "$p" '{"hook_event_name":"StopFailure"}'
    assert_eq "Claude · AB-9-y${tab}Turn ended with an error" "$(last_log)" "failure body"
    long=$(printf 'a%.0s' $(seq 150))
    msg=$(jq -nc --arg m "$long"$'\nsecond line\nthird line' '{hook_event_name:"Stop",last_assistant_message:$m}')
    hook "$p" "$msg"
    assert_eq "Claude · AB-9-y${tab}${long:0:100}" "$(last_log)" "done body is first line, 100 chars"
    n=$(log_lines)
    hook "$p" '{"hook_event_name":"UserPromptSubmit"}'
    hook "$p" '{"hook_event_name":"PostToolUse","tool_name":"Bash"}'
    assert_eq "$n" "$(log_lines)" "working events do not notify"
}

test_notify_looking_suppressed() {
    start_server
    local p
    p=$(agent_pane)
    source "$SCRIPTS/claude-tmux-hook"
    is_looking() { return 0; }
    COCKPIT_NOTIFY_LOG=$TMP/notify.log handle_event "$p" <<<'{"hook_event_name":"Stop"}'
    assert_eq done "$(opt "$p" @claude_state)" "state still recorded"
    assert_eq "" "$(opt "$p" @claude_attn)" "no attn while looking"
    assert_eq 0 "$(log_lines)" "no notification while looking"
}

test_osc99_escaping() {
    source "$SCRIPTS/claude-tmux-hook"
    local input=$'a\e]0;pwned\a"b' out rest payload
    out=$(osc99 "t" "$input")
    assert_eq $'\e]99;' "${out:0:5}" "starts with OSC 99"
    assert_eq $'\e\\' "${out: -2}" "ends with ST"
    assert_contains "$out" "e=1" "base64 payload flag"
    rest=${out#*p=body;}
    payload=${rest%%$'\e'*}
    assert_eq "$input" "$(printf '%s' "$payload" | base64 -D)" "body round-trips"
    assert_not_contains "$out" $'\a' "no raw BEL"
    assert_eq 4 "$(printf '%s' "$out" | tr -cd '\033' | wc -c | tr -d ' ')" "only framing ESCs"
}


waiting_pane() {
    local p
    p=$(agent_pane)
    tmux set -p -t "$p" @claude_state waiting
    tmux set -p -t "$p" @claude_attn 1
    echo "$p"
}

start_pulse_bg() { COCKPIT_PULSE_INTERVAL=0.1 "$SCRIPTS/claude-tmux-pulse" "${TMUX%%,*}" & }

gone_within_1s() {
    local i
    for i in 1 2 3 4 5 6 7 8 9 10; do
        pulses "$1" >/dev/null || return 0
        sleep 0.1
    done
    return 1
}

test_pulse_toggles() {
    start_server
    local p seen="" i
    p=$(waiting_pane)
    start_pulse_bg
    for i in 1 2 3 4 5 6; do
        sleep 0.1
        seen="$seen $(opt "$p" @claude_glow)"
    done
    assert_contains "$seen" "#e0a040" "bright amber shown"
    assert_contains "$seen" "#7a5a28" "dim amber shown"
    assert_contains "$seen" "#" "pulse sets the per-pane shade the border format reads"
}

running() { local s; s=$(ps -o stat= -p "$1" 2>/dev/null) && [ "${s#Z}" = "$s" ]; }

test_pulse_single_instance() {
    start_server
    local a b alive=0
    waiting_pane >/dev/null
    start_pulse_bg
    a=$!
    start_pulse_bg
    b=$!
    sleep 0.4
    running "$a" && alive=$((alive + 1))
    running "$b" && alive=$((alive + 1))
    assert_eq 1 "$alive" "one pulse loop survives"
}

test_pulse_stops() {
    start_server
    local p
    p=$(waiting_pane)
    start_pulse_bg
    sleep 0.2
    pulses "${TMUX%%,*}" >/dev/null || fail "pulse not running"
    tmux set -pu -t "$p" @claude_attn
    gone_within_1s "${TMUX%%,*}" || fail "pulse still running after attn cleared"
    assert_eq "" "$(tmux show -gqv @claude_pulse_pid)" "pid option cleared"
}

test_pulse_server_killed() {
    start_server
    local s=${TMUX%%,*}
    waiting_pane >/dev/null
    start_pulse_bg
    sleep 0.2
    pulses "$s" >/dev/null || fail "pulse not running"
    tmux -S "$SOCK" kill-server
    gone_within_1s "$s" || fail "pulse outlived its tmux server"
}

test_hook_starts_pulse() {
    start_server
    local p
    p=$(agent_pane)
    hook "$p" '{"hook_event_name":"PermissionRequest","tool_name":"Bash"}'
    sleep 0.2
    pulses "${TMUX%%,*}" >/dev/null || fail "hook did not start the pulse"
}


agent() {
    tmux set -p -t "$1" @claude_state "$2"
    tmux set -p -t "$1" @claude_ts "$3"
    [ "$4" = 1 ] && tmux set -p -t "$1" @claude_attn 1
    tmux set -p -t "$1" @claude_label "L$3"
}

test_jump_order() {
    start_server
    local p1 p2 p3 p4 p5 out
    p1=$(agent_pane) p2=$(agent_pane) p3=$(agent_pane) p4=$(agent_pane) p5=$(agent_pane)
    agent "$p1" idle 1 0
    agent "$p2" working 2 0
    agent "$p3" done 3 1
    agent "$p4" waiting 4 1
    agent "$p5" waiting 5 0
    out=$("$SCRIPTS/claude-tmux-jump" list)
    assert_eq "$p5 $p4 $p3 $p2 $p1" "$(echo $(cut -f1 <<<"$out"))" "pane order"
    assert_eq "◆ waiting|◆ waiting|✓ done|● working|○ idle" "$(cut -f2 <<<"$out" | paste -sd'|' -)" "state column"
    assert_contains "$(head -1 <<<"$out")" "L5" "label column"
    out=$("$SCRIPTS/claude-tmux-jump" list --attn)
    assert_eq "$p4 $p3" "$(echo $(cut -f1 <<<"$out"))" "attn-only list"
}

test_jump_stale() {
    start_server
    local s
    s=$(tmux new-window -d -t t: -P -F '#{pane_id}' zsh)
    sleep 0.3
    agent "$s" done 9 1
    assert_eq "" "$("$SCRIPTS/claude-tmux-jump" list)" "shell-foreground pane not listed"
    assert_eq "L9" "$(opt "$s" @claude_label)" "label kept for a suspended Claude"
    assert_eq "" "$(opt "$s" @claude_attn)" "its glow is cleared"
}

test_review_shell_pane_hidden() {
    start_server "$ROOT/tmux/tmux.conf"
    local s
    s=$(tmux new-window -d -t t: -P -F '#{pane_id}' zsh)
    sleep 0.3
    agent "$s" done 9 1
    assert_not_contains "$(header "$s")" "✓" "no agent header on a shell"
    assert_not_contains "$(header "$s")" "· done" "no agent state on a shell"
    assert_not_contains "$(tmux display -p -t t: '#{E:status-right}')" "✓" "no status marker"
    tmux set -p -t "$s" @claude_state waiting
    start_pulse_bg
    gone_within_1s "${TMUX%%,*}" || fail "pulse ignores a shell pane"
}

test_review_question_one_banner() {
    start_server
    local p
    p=$(agent_pane)
    hook "$p" '{"hook_event_name":"PreToolUse","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Which DB?"}]}}'
    hook "$p" '{"hook_event_name":"PermissionRequest","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Which DB?"}]}}'
    assert_eq 1 "$(log_lines)" "one notification per question"
}

test_review_clear_and_compact() {
    start_server
    local p
    git init -q -b AB-5-z "$TMP/repo"
    p=$(agent_pane)
    hook "$p" '{"hook_event_name":"SessionStart","source":"startup","cwd":"'"$TMP/repo"'"}'
    hook "$p" '{"hook_event_name":"UserPromptSubmit"}'
    hook "$p" '{"hook_event_name":"SessionStart","source":"compact","cwd":"'"$TMP/repo"'"}'
    assert_eq working "$(opt "$p" @claude_state)" "compaction keeps working"
    hook "$p" '{"hook_event_name":"SessionStart","source":"clear","cwd":"'"$TMP/repo"'"}'
    hook "$p" '{"hook_event_name":"SessionEnd","reason":"clear"}'
    assert_eq idle "$(opt "$p" @claude_state)" "late SessionEnd(clear) keeps the pane"
    assert_eq AB-5-z "$(opt "$p" @claude_label)" "label survives /clear"
    hook "$p" '{"hook_event_name":"SessionEnd","reason":"prompt_input_exit"}'
    assert_eq "" "$(opt "$p" @claude_state)" "real exit still clears"
}

test_border_only_needy_pane() {
    start_server "$ROOT/tmux/tmux.conf"
    local a b
    a=$(tmux display -p -t t '#{pane_id}')
    b=$(tmux split-window -d -h -t "$a" -P -F '#{pane_id}' 'sleep 600')
    tmux respawn-pane -k -t "$a" 'sleep 600'
    hook "$a" '{"hook_event_name":"Stop","last_assistant_message":"x"}'
    assert_contains "$(tmux display -p -t "$a" '#{E:pane-border-style}')" "#7aa2d8" "done pane border is blue"
    assert_not_contains "$(tmux display -p -t "$b" '#{E:pane-border-style}')" "#7aa2d8" "neighbour border untouched"
    assert_not_contains "$(tmux display -p -t "$b" '#{E:pane-active-border-style}')" "#7aa2d8" "neighbour active border untouched"
    assert_eq "" "$(tmux show -wqv -t t pane-border-style)" "nothing written at window scope"
    assert_eq "" "$(tmux show -pqv -t "$a" pane-border-style)" "nothing written at pane scope"
    tmux set -p -t "$a" @claude_state waiting
    tmux set -p -t "$a" @claude_glow "#7a5a28"
    assert_contains "$(tmux display -p -t "$a" '#{E:pane-border-style}')" "#7a5a28" "waiting border follows the pulse"
}

test_render_glow_on_needy_pane_only() {
    command -v python3 >/dev/null || { echo "SKIP $CURRENT: no python3" && return 0; }
    start_server "$ROOT/tmux/tmux.conf"
    local a b c out bright dim edge
    tmux set -as terminal-features ',*:RGB'
    a=$(tmux display -p -t t '#{pane_id}')
    tmux respawn-pane -k -t "$a" 'sleep 600'
    b=$(tmux split-window -h -t "$a" -P -F '#{pane_id}' 'sleep 600')
    c=$(tmux split-window -v -t "$b" -P -F '#{pane_id}' 'sleep 600')
    tmux select-pane -t "$c"
    out=$TMP/render.out
    (sleep 8 | TERM=xterm-256color script -q "$out" tmux -S "${TMUX%%,*}" attach -t t >/dev/null 2>&1 &)
    sleep 1
    [ "$(tmux list-clients | wc -l | tr -d ' ')" = 1 ] || fail "render client attached"
    COCKPIT_PULSE_INTERVAL=0.75 hook "$a" '{"hook_event_name":"PermissionRequest","tool_name":"Bash"}'
    sleep 3
    tmux list-clients -F '#{client_tty}' | xargs -I{} tmux detach-client -t {}
    edge=$(($(tmux display -p -t "$a" '#{pane_right}') + 2))
    read -r bright _ bmax <<<"$(python3 -I "$ROOT/scripts/tests/border_cells.py" "$out" '#e0a040')"
    read -r dim _ dmax <<<"$(python3 -I "$ROOT/scripts/tests/border_cells.py" "$out" '#7a5a28')"
    [ "$bright" -gt 0 ] || fail "needy pane border drawn bright"
    [ "$dim" -gt 0 ] || fail "pulse redraws the border dim"
    [ "$bmax" -le "$edge" ] && [ "$dmax" -le "$edge" ] || fail "glow leaked past the needy pane (cols up to $bmax/$dmax, edge $edge)"
}

test_review_t_fetches_first() {
    source "$SCRIPTS/t"
    local r d want
    r=$(cd "$TMP" && pwd -P)
    make_origin "$r"
    git clone -q "$r/origin.git" "$r/other" 2>/dev/null
    (cd "$r/other" && git checkout -qb AB-300-remote && echo x >work.txt && git add work.txt &&
        git -c user.email=t@t -c user.name=t commit -qm "colleague work" && git push -q origin AB-300-remote) >/dev/null 2>&1
    want=$(git -C "$r/other" rev-parse HEAD)
    d=$(new_worktree "$r/app" AB-300-remote 2>/dev/null)
    assert_eq "$want" "$(git -C "$d" rev-parse HEAD)" "worktree is on the colleague's commit"
}


header() { tmux display -p -t "$1" '#{E:pane-border-format}'; }

test_conf_visuals() {
    start_server "$ROOT/tmux/tmux.conf"
    local p q h
    assert_eq "top" "$(tmux show -gv pane-border-status)" "header strip on"
    p=$(agent_pane)
    tmux set -p -t "$p" @claude_label AB-197
    agent "$p" waiting 5 1
    tmux set -p -t "$p" @claude_label AB-197
    h=$(header "$p")
    assert_contains "$h" "◆ AB-197 · needs you" "waiting header"
    assert_contains "$h" "#e0a040" "waiting + attn is amber when glow empty"
    tmux set -p -t "$p" @claude_glow "#7a5a28"
    assert_contains "$(header "$p")" "#7a5a28" "waiting + attn follows the pulse"
    tmux set -pu -t "$p" @claude_attn
    assert_contains "$(header "$p")" "#e0a040" "seen waiting stays amber"
    agent "$p" done 6 1
    tmux set -p -t "$p" @claude_label AB-197
    h=$(header "$p")
    assert_contains "$h" "✓ AB-197 · done" "done header"
    assert_contains "$h" "#7aa2d8" "done + attn is blue"
    tmux set -pu -t "$p" @claude_attn
    tmux set -p -t "$p" @claude_state working
    h=$(header "$p")
    assert_contains "$h" "● AB-197 · working" "working header"
    assert_contains "$h" "#5c5e66" "working is dim"
    q=$(agent_pane)
    assert_contains "$(header "$q")" "sleep" "non-Claude pane shows its command"
    tmux new-session -d -s other
    p=$(tmux new-window -d -t other: -P -F '#{pane_id}' 'sleep 600')
    agent "$p" waiting 7 1
    assert_contains "$(tmux display -p -t t: '#{E:status-right}')" "◆" "status-right counts other sessions"
    assert_contains "$(tmux display -p -t "$p" '#{E:window-status-format}')" "◆" "window marker"
    assert_contains "$(tmux show-hooks -gw)" "pane-focus-in" "focus-in hook"
    assert_contains "$(tmux show-hooks -gw)" "pane-focus-out" "focus-out hook"
    assert_contains "$(tmux list-keys -T prefix a)" "claude-tmux-jump pick" "prefix+a"
    assert_contains "$(tmux list-keys -T prefix u)" "claude-tmux-jump next" "prefix+u"
}


test_t_names() {
    source "$SCRIPTS/t"
    assert_eq /x/my-app-ab197 "$(worktree_dir /x/my-app AB-197-sub-models)" "jira key folder"
    assert_eq /x/my-app-feature-login-fix "$(worktree_dir /x/my-app feature/Login_Fix)" "slug folder"
    assert_eq a-b "$(slug '--A b--')" "slug trims"
    assert_eq -Users-me-dotfiles "$(project_key /Users/me/dotfiles)" "transcript folder key"
}

test_t_root() {
    source "$SCRIPTS/t"
    assert_eq "$(cd /tmp && pwd)" "$(cd /tmp && env -u TMUX bash -c "source '$SCRIPTS/t'; cockpit_root")" "outside tmux: cwd"
    start_server
    assert_eq "$(tmux display -p -t t '#{session_path}')" "$(cockpit_root)" "no option: session path"
    tmux set -t t @cockpit_root /r
    assert_eq /r "$(cockpit_root)" "inherited root"
}

make_origin() {
    git init -q --bare -b master "$1/origin.git"
    git clone -q "$1/origin.git" "$1/app" 2>/dev/null
    (cd "$1/app" && printf '.env\nconfig/local.php\n' >.gitignore && git add .gitignore &&
        git -c user.email=t@t -c user.name=t commit -qm init && git push -q origin master &&
        git remote set-head origin master) >/dev/null 2>&1
    echo "SECRET=1" >"$1/app/.env"
}

test_t_worktree() {
    source "$SCRIPTS/t"
    local r d err before
    r=$(cd "$TMP" && pwd -P)
    make_origin "$r"
    d=$(new_worktree "$r/app" AB-200-thing 2>/dev/null)
    assert_eq "$r/app-ab200" "$d" "new worktree folder"
    assert_eq AB-200-thing "$(git -C "$d" branch --show-current)" "new branch"
    [ -f "$d/.env" ] || fail ".env copied"
    git -C "$d" rev-parse -q --verify '@{u}' >/dev/null 2>&1 && fail "new branch must not track origin/master"
    assert_eq "$r/app" "$(new_worktree "$r/app" master 2>/dev/null)" "checked-out branch opens its folder"
    mkdir "$r/app-ab201"
    before=$(git -C "$r/app" worktree list)
    err=$(new_worktree "$r/app" AB-201-x 2>&1 >/dev/null) && fail "collision must fail"
    assert_contains "$err" "already exists" "collision message"
    assert_eq "$before" "$(git -C "$r/app" worktree list)" "collision changes nothing"
    mkdir -p "$r/app/config" && echo "<?php" >"$r/app/config/local.php"
    echo "config/local.php" >"$r/app/.worktreeinclude"
    d=$(new_worktree "$r/app" AB-202-y 2>/dev/null)
    [ -f "$d/config/local.php" ] || fail ".worktreeinclude file copied"
    [ -f "$d/.env" ] && fail ".env not copied when .worktreeinclude exists"
    local list
    list=$(list_candidates "$r")
    assert_contains "$list" "$r/app-ab200" "worktree listed"
    assert_eq "+ new worktree" "$(tail -1 <<<"$list")" "new entry last"
}

test_t_claude_cmd() {
    source "$SCRIPTS/t"
    local HOME=$TMP/home
    assert_eq "claude -n 'B'" "$(claude_cmd /w/x B)" "fresh folder names the session"
    mkdir -p "$HOME/.claude/projects/$(project_key /w/x)" && touch "$HOME/.claude/projects/$(project_key /w/x)/a.jsonl"
    assert_eq "claude --continue" "$(claude_cmd /w/x B)" "folder with history continues"
}

test_t_branch_cannot_inject() {
    source "$SCRIPTS/t"
    local HOME=$TMP/home
    assert_eq "claude -n 'x-touch-tmp-pwned'" "$(claude_cmd /w/y "x';touch /tmp/pwned;'")" "shell metacharacters never reach the typed command"
    assert_eq "claude -n 'feature/AB-1_fix.v2'" "$(claude_cmd /w/y feature/AB-1_fix.v2)" "normal branch names unchanged"
}

test_t_worktreeinclude_stays_inside_repo() {
    source "$SCRIPTS/t"
    local r d
    r=$(cd "$TMP" && pwd -P)
    make_origin "$r"
    echo "top secret" >"$r/secret.txt"
    printf '%s\n' "../secret.txt" "$r/secret.txt" ".env" >"$r/app/.worktreeinclude"
    d=$(new_worktree "$r/app" AB-210-z 2>/dev/null)
    [ -f "$d/.env" ] || fail "in-repo entry still copied"
    assert_eq "" "$(find "$d" -name secret.txt)" "files outside the repo are never copied into the worktree"
    true
}

test_t_session() {
    source "$SCRIPTS/t"
    local d w right
    start_server
    d=$(cd "$TMP" && pwd -P)/app-ab200
    mkdir -p "$d"
    open_session "$d" /root "echo hi"
    tmux has-session -t =app-ab200 || fail "session created"
    assert_eq 2 "$(tmux list-panes -t =app-ab200 | wc -l | tr -d ' ')" "two panes"
    assert_eq /root "$(tmux show -qv -t app-ab200 @cockpit_root)" "root inherited"
    w=$(tmux display -p -t app-ab200: '#{window_width}')
    right=$(tmux display -p -t app-ab200:.1 '#{pane_width}')
    [ $((right * 100 / w)) -ge 38 ] && [ $((right * 100 / w)) -le 41 ] || fail "shell pane ~40% (got $right of $w)"
    sleep 0.5
    assert_contains "$(tmux capture-pane -p -t app-ab200:.0)" "echo hi" "Claude command typed in the left pane"
}


test_statusline() {
    local b out
    b=$(git -C "$ROOT" branch --show-current)
    out=$(echo '{"cwd":"'"$ROOT"'","context_window":{"used_percentage":42.4}}' | bash ~/.claude/statusline-command.sh)
    assert_contains "$out" "$b · 42% ctx" "branch and context usage"
    out=$(echo '{"cwd":"'"$ROOT"'"}' | bash ~/.claude/statusline-command.sh)
    assert_contains "$out" "$b" "branch without context data"
    assert_not_contains "$out" "ctx" "no ctx without context data"
}


test_hook_agents_working() {
    start_server
    local p
    p=$(agent_pane)
    hook "$p" '{"hook_event_name":"Stop","last_assistant_message":"Waiting on agents","background_tasks":[{"id":"a1","type":"subagent","status":"running"}]}'
    assert_eq agents "$(opt "$p" @claude_state)" "background agent keeps the pane busy"
    assert_eq "" "$(opt "$p" @claude_attn)" "no glow while agents work"
    assert_eq 0 "$(log_lines)" "no notification while agents work"
    hook "$p" '{"hook_event_name":"Stop","last_assistant_message":"All done","background_tasks":[]}'
    assert_eq done "$(opt "$p" @claude_state)" "done once agents finish"
    assert_eq 1 "$(log_lines)" "done notifies"
    hook "$p" '{"hook_event_name":"Stop","last_assistant_message":"Server up","background_tasks":[{"id":"s1","type":"shell","status":"running","command":"php artisan serve"}]}'
    assert_eq done "$(opt "$p" @claude_state)" "a background shell (dev server) does not block done"
}

test_conf_agents_working() {
    start_server "$ROOT/tmux/tmux.conf"
    local p
    p=$(agent_pane)
    agent "$p" agents 3 0
    tmux set -p -t "$p" @claude_label AB-197
    assert_contains "$(header "$p")" "◐ AB-197 · agents working" "agents header"
    assert_contains "$(header "$p")" "#5c5e66" "agents is dim"
    assert_eq "◐ agents" "$("$SCRIPTS/claude-tmux-jump" list | cut -f2)" "listed as agents"
}

stray_comments() {
    awk 'NR == 1 && /^#!/ { hdr = 1; next }
         hdr && /^#/ { next }
         { hdr = 0 }
         /^[[:space:]]*#/ || /[^$"\047{(^]#[[:space:]][[:alpha:]]/ { print FILENAME ":" FNR ": " $0 }' "$1"
}

test_no_comments() {
    local f found="" sect
    for f in claude-tmux-hook claude-tmux-pulse claude-tmux-jump t tests/cockpit-test.sh; do
        found="$found$(stray_comments "$SCRIPTS/$f")"
    done
    found="$found$(grep -n '[[:space:]]#[[:space:]]' "$ROOT/install")"
    sect=$(awk '/^# Claude cockpit$/ { on = 1; next } /^# Key Bindings$/ { on = 0 }
        on && /^#/ && !/^#-+$/ { print "tmux.conf:" NR ": " $0 }' "$ROOT/tmux/tmux.conf")
    assert_eq "" "$found$sect" "comments left in cockpit code"
}


trap 'stop_server; rm -rf "$BASE_TMP"' EXIT

names=("$@")
[ ${#names[@]} -gt 0 ] || names=($(declare -F | awk '{print $3}' | grep '^test_'))
failed=0
for CURRENT in "${names[@]}"; do
    TMP=$BASE_TMP/$CURRENT && mkdir -p "$TMP"
    if ("$CURRENT"); then echo "PASS $CURRENT"; else failed=$((failed + 1)); fi
    stop_server
done
echo "---- ${#names[@]} run, $failed failed"
[ "$failed" -eq 0 ]
