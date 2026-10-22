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

step "Type roles"
# Text takes the named roles in DesignSystem.swift (D-34): SF Pro on the system's text
# styles, New York for display, figures that scale. A raw point size anywhere else is a
# size the scale never chose.
if grep -rn --include='*.swift' "\.system(size:" "$PACKAGE_PATH/Sources/AntipodesUI" \
    | grep -v "/DesignSystem.swift:"; then
    fail "a raw .system(size:) outside DesignSystem.swift — use a type role (D-34)"
fi
note "only the named type roles are used"

