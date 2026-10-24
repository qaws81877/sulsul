#!/usr/bin/env bash
# Start or stop an isolated Sulsul Dev app for verification.
#
#   dev-app.sh start   run `make` first; launches the built app by absolute path with a scratch data
#                      folder, skips onboarding, prints the PID
#   dev-app.sh stop    stops only the instance started here, deletes its scratch folder and puts the
#                      onboarding key back as it was
#
# It refuses to start when another Sulsul Dev is already running, so a session never drives (or kills)
# an instance it did not start. The scratch folder isolates Application Support only: the defaults
# domain stays shared with `make dev`. The env var is not inherited when the app relaunches itself
# (Sparkle's Install & Relaunch), so a relaunched copy opens the default Dev folder and has a new PID
# that `stop` does not know.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
APP="$ROOT/.build.noindex/Build/Products/Debug/Sulsul Dev.app"
PROCESS="Sulsul Dev.app/Contents/MacOS/Sulsul Dev"
DOMAIN="com.qaws81877.sulsul.dev"
KEY="hasCompletedOnboardingV2"
STATE="${TMPDIR:-/tmp}/sulsul-verify-state"

fail() {
    echo "dev-app: $1" >&2
    exit 1
}

case "${1:-}" in
start)
    [[ -d "$APP" ]] || fail "not built: $APP (run make first)"
    [[ ! -e "$STATE" ]] || fail "already started ($(cut -d' ' -f1 "$STATE")); run stop first"
    running="$(pgrep -f "$PROCESS" | head -1)"
    [[ -z "$running" ]] || fail "a Sulsul Dev is already running (pid $running); do not drive an instance you did not start"

    prior="$(defaults read "$DOMAIN" "$KEY" 2>/dev/null || true)"
    scratch="verify-$(date +%s)"
    defaults write "$DOMAIN" "$KEY" -bool YES
    open -n -a "$APP" --env "SULSUL_SUPPORT_DIR_NAME=$scratch"

    pid=""
    for _ in $(seq 1 30); do
        pid="$(pgrep -f "$PROCESS" | head -1)"
        [[ -n "$pid" ]] && break
        sleep 1
    done
    if [[ -z "$pid" ]]; then
        if [[ -z "$prior" ]]; then defaults delete "$DOMAIN" "$KEY" 2>/dev/null; else defaults write "$DOMAIN" "$KEY" -bool "$([[ "$prior" == 1 ]] && echo YES || echo NO)"; fi
        fail "the app did not start"
    fi
    printf '%s %s %s\n' "$pid" "$scratch" "${prior:-none}" >"$STATE"
    echo "started pid=$pid data=$HOME/Library/Application Support/$scratch"
    ;;
stop)
    [[ -e "$STATE" ]] || fail "nothing was started by this script"
    read -r pid scratch prior <"$STATE"
    if ps -p "$pid" -o command= 2>/dev/null | grep -qF "$PROCESS"; then
        kill -TERM "$pid"
        for _ in $(seq 1 10); do
            kill -0 "$pid" 2>/dev/null || break
            sleep 1
        done
        kill -0 "$pid" 2>/dev/null && kill -KILL "$pid"
    fi
    if [[ "$scratch" == verify-* ]]; then
        rm -rf "$HOME/Library/Application Support/$scratch"
    fi
    if [[ "$prior" == none ]]; then
        defaults delete "$DOMAIN" "$KEY" 2>/dev/null
    else
        defaults write "$DOMAIN" "$KEY" -bool "$([[ "$prior" == 1 ]] && echo YES || echo NO)"
    fi
    rm -f "$STATE"
    echo "stopped pid=$pid, removed $scratch, onboarding key restored"
    ;;
*)
    echo "usage: $0 start|stop" >&2
    exit 2
    ;;
esac
