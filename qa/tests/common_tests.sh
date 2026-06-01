#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../lib/common.sh
. "${ROOT_DIR}/qa/lib/common.sh"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

assert_file() {
    [[ -f "$1" ]] || fail "expected file: $1"
}

test_write_defaults() {
    local home
    home="$(mktemp -d "${TMPDIR:-/tmp}/qm-qa-defaults.XXXXXX")"
    local domain="dev.tjzhou.QuotaMonitor.QATest.$RANDOM.$$"
    trap 'HOME="$home" defaults delete "$domain" >/dev/null 2>&1 || true; rm -rf "$home"' RETURN

    qm_write_defaults "$home" "$domain"

    local language developer_mode keychain_policy providers_done
    language="$(HOME="$home" defaults read "$domain" app.language)"
    developer_mode="$(HOME="$home" defaults read "$domain" settings.developerModeEnabled)"
    keychain_policy="$(HOME="$home" defaults read "$domain" settings.keychainPolicy)"
    providers_done="$(HOME="$home" defaults read "$domain" onboarding.providersDone)"

    [[ "$language" == "en" ]] || fail "language default was $language"
    [[ "$developer_mode" == "1" ]] || fail "developer mode default was $developer_mode"
    [[ "$keychain_policy" == "never" ]] || fail "keychain policy default was $keychain_policy"
    [[ "$providers_done" == "1" ]] || fail "provider onboarding default was $providers_done"
}

test_seed_fixtures() {
    local home
    home="$(mktemp -d "${TMPDIR:-/tmp}/qm-qa-fixtures.XXXXXX")"
    trap 'rm -rf "$home"' RETURN

    qm_seed_fixtures "$home"

    assert_file "$home/.codex/sessions/qa/rollout-2026-06-01T00-00-00-019aa0fd-1111-7000-8000-aaaaaaaaaaaa.jsonl"
    assert_file "$home/.claude/projects/-Volumes-SamsungDisk-Code-quota-monitor/qa-claude-session.jsonl"
    assert_file "$home/.config/claude/projects/-Volumes-SamsungDisk-Code-quota-monitor/qa-claude-config-session.jsonl"
}

test_write_defaults
test_seed_fixtures
echo "common_tests: ok"
