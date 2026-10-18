#!/usr/bin/env bash
# Formats and lints the Swift sources. Pass --check to verify without writing.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

MODE_ARGS=()
LINT_ONLY=0
for argument in "$@"; do
    case "$argument" in
        --check) MODE_ARGS+=(--lint); LINT_ONLY=1 ;;
        *) MODE_ARGS+=("$argument") ;;
    esac
done

if command -v swiftformat >/dev/null 2>&1; then
    step "SwiftFormat"
    swiftformat "$PACKAGE_PATH" "$REPO_ROOT/App" ${MODE_ARGS+"${MODE_ARGS[@]}"}
else
    note "swiftformat not installed, skipping (brew install swiftformat)"
fi

if command -v swiftlint >/dev/null 2>&1; then
    step "SwiftLint"
    if [[ "$LINT_ONLY" -eq 1 ]]; then
        swiftlint lint --strict --quiet
    else
        swiftlint lint --quiet
    fi
else
    note "swiftlint not installed, skipping (brew install swiftlint)"
fi
