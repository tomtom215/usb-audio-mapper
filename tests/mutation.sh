#!/usr/bin/env bash
# Mutation check: re-introduce known defects into a copy of the script and
# require the bats suite to fail for each one. A surviving mutant means the
# tests no longer guard that behavior.
# Usage: tests/mutation.sh
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
src="$here/../usb-audio-mapper.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# name|sed expression (single-quoted on purpose: literal sed programs)
# shellcheck disable=SC2016
mutants=(
    'comment-and-rule-on-one-line|s/^\(        printf .# usb-audio-mapper: name=%s usb=%s:%s port=%s path=%s desc=%s\)\\n/\1/'
    'no-idempotence-guard|s/ATTR{id}!="%s", //; s/"card\*" "\$name" "\$name" "\$name"/"card*" "$name" "$name"/'
    'loose-port-pattern|s/^readonly USB_PORT_RE=.*/readonly USB_PORT_RE=-/'
    'names-up-to-32|s/^readonly MAX_NAME_LENGTH=15/readonly MAX_NAME_LENGTH=32/'
    'allow-card-prefix|s/elif \[\[ "\$name" == card\* \]\]; then/elif false; then/'
    'no-legacy-migration|s/} else if (index(line, "ATTR{id}=\\"" name "\\"") > 0) {/} else if (0) {/'
    'no-lock|s/^    if command -v flock >\/dev\/null 2>&1; then/    if false; then/'
    'no-line-assertion|s/^assert_rules_safe() {/assert_rules_safe() { return 0;/'
    'unsanitized-description|s/desc=\$(sanitize_desc "\$desc")/desc="$desc"/'
    'verify-failure-ignored|s/return "\$E_VERIFY"/return 0/'
    'silent-port-fallback|s/port=\$(normalize_usb_port "\$port") || error_exit "Invalid USB port (see --list for valid ports)." "\$E_USAGE"/port=$(normalize_usb_port "$port" 2>\/dev\/null) || port=""/'
    'ambiguity-ignored|s/^            elif ((\${#ports\[@\]} > 1)); then/            elif false; then/'
    'id-path-never-used|s/^    elif \[\[ -n "\$target" \]\] \&\& idpath=\$(card_id_path "\$target"); then/    elif false; then/'
    'id-path-borrowed-from-other-device|s/^    if \[\[ -n "\$tport" \&\& .*/    if [[ -n "$tport" ]]; then/'
)

survivors=0
for m in "${mutants[@]}"; do
    name=${m%%|*}
    expr=${m#*|}
    sed "$expr" "$src" >"$work/$name.sh"
    if cmp -s "$src" "$work/$name.sh"; then
        echo "ERROR: mutant '$name' did not apply; update its expression" >&2
        exit 2
    fi
    failed=$(MAPPER_UNDER_TEST="$work/$name.sh" bats "$here" 2>/dev/null | grep -c '^not ok' || true)
    if ((failed > 0)); then
        echo "killed   $name ($failed failing tests)"
    else
        echo "SURVIVED $name"
        survivors=$((survivors + 1))
    fi
done
exit $((survivors > 0))
