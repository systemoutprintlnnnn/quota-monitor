#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="QuotaMonitor"
BUNDLE_ID="dev.tjzhou.QuotaMonitor"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="${ROOT_DIR}/.build/${APP_NAME}.app"
APP_BINARY="${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

usage() {
    cat >&2 <<EOF
usage: $0 [run|--debug|--logs|--telemetry|--verify|--qa]
EOF
}

stop_running_app() {
    pkill -x "$APP_NAME" >/dev/null 2>&1 || true
}

build_app() {
    (cd "$ROOT_DIR" && ./build.sh debug)
}

open_app() {
    local args=(-n)
    if [[ "${QUOTAMONITOR_QA_MODE:-}" == "1" ]]; then
        args+=(--env "QUOTAMONITOR_QA_MODE=1")
        args+=(--env "QUOTAMONITOR_QA_OUTPUT_DIR=${QUOTAMONITOR_QA_OUTPUT_DIR:?}")
        args+=(--env "QUOTAMONITOR_QA_HOME=${QUOTAMONITOR_QA_HOME:?}")
        args+=(--env "QUOTAMONITOR_QA_DEFAULTS_SUITE=${QUOTAMONITOR_QA_DEFAULTS_SUITE:?}")
        if [[ -n "${QUOTAMONITOR_QA_STEPS:-}" ]]; then
            args+=(--env "QUOTAMONITOR_QA_STEPS=${QUOTAMONITOR_QA_STEPS}")
        fi
        local launch_home="${QUOTAMONITOR_QA_LAUNCH_HOME:-${HOME:-}}"
        if [[ -n "$launch_home" ]]; then
            args+=(--env "HOME=${launch_home}")
        fi
        if [[ -n "${CODEX_HOME:-}" ]]; then
            args+=(--env "CODEX_HOME=${CODEX_HOME}")
        fi
    fi
    /usr/bin/open "${args[@]}" "$APP_BUNDLE"
}

verify_process() {
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
}

case "$MODE" in
    run)
        stop_running_app
        build_app
        open_app
        ;;
    --debug|debug)
        stop_running_app
        build_app
        lldb -- "$APP_BINARY"
        ;;
    --logs|logs)
        stop_running_app
        build_app
        open_app
        /usr/bin/log stream --info --style compact --predicate "process == \"${APP_NAME}\""
        ;;
    --telemetry|telemetry)
        stop_running_app
        build_app
        open_app
        /usr/bin/log stream --info --style compact --predicate "subsystem == \"${BUNDLE_ID}\""
        ;;
    --verify|verify)
        stop_running_app
        build_app
        open_app
        verify_process
        ;;
    --qa|qa)
        export QUOTAMONITOR_QA_MODE=1
        : "${QUOTAMONITOR_QA_OUTPUT_DIR:?QUOTAMONITOR_QA_OUTPUT_DIR is required for --qa}"
        : "${QUOTAMONITOR_QA_HOME:?QUOTAMONITOR_QA_HOME is required for --qa}"
        : "${QUOTAMONITOR_QA_DEFAULTS_SUITE:?QUOTAMONITOR_QA_DEFAULTS_SUITE is required for --qa}"
        stop_running_app
        build_app
        open_app
        verify_process
        ;;
    *)
        usage
        exit 2
        ;;
esac
