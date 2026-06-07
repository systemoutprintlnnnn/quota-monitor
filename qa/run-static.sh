#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -f "${HOME}/.swiftly/env.sh" ]]; then
    # shellcheck disable=SC1090
    . "${HOME}/.swiftly/env.sh"
fi

"${ROOT_DIR}/qa/tests/common_tests.sh"
(cd "$ROOT_DIR" && python3 -m unittest discover tools/tests)

VERSION="$(tr -d '[:space:]' <"${ROOT_DIR}/Resources/VERSION")"
(cd "$ROOT_DIR" && python3 tools/validate-release-notes.py "$VERSION" CHANGELOG.md CHANGELOG.zh-Hans.md)

(cd "$ROOT_DIR" && git diff --check)
(cd "$ROOT_DIR" && swift test --disable-keychain)
