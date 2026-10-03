#!/usr/bin/env bash
# Run the bats suite with the mapper executed by several GNU bash releases.
# Each release is built from a checksum-pinned ftp.gnu.org tarball and cached.
# bash 3.2 (the macOS default) is unsupported; it is checked for a clean
# refusal instead of running the suite.
#
# Usage: tests/bash-matrix.sh [CACHE_DIR] [VERSION...]
#   default versions: all pinned below; CACHE_DIR default: .cache/bash
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
cache=${1:-$here/../.cache/bash}
shift || true

declare -A sha256=(
    ["3.2.57"]=3fa9daf85ebf35068f090ce51283ddeeb3c75eb5bc70b1a4a7cb05868bfe06a4
    ["4.2.53"]=e81b256ba44132db14c0d81c558ceb64a5c373414fe58d2e94b1cb487985cb8b
    ["4.3.30"]=317881019bbf2262fb814b7dd8e40632d13c3608d2f237800a8828fbb8a640dd
    ["4.4.18"]=604d9eec5e4ed5fd2180ee44dd756ddca92e0b6aa4217bbab2b6227380317f23
    ["5.0"]=b4a80f2ac66170b2913efbfb9f2594f1f76c7b1afd11f799e22035d63077fb4d
    ["5.1.16"]=5bac17218d3911834520dad13cd1f85ab944e1c09ae1aba55906be1f8192f558
    ["5.2.37"]=9599b22ecd1d5787ad7d3b7bf0c59f312b3396d1e281175dd1f8a4014da621ff
    ["5.3"]=0d5cd86965f869a26cf64f4b71be7b96f90a3ba8b3d74e27e8e9d9d5550f31ba
)
versions=("$@")
if ((${#versions[@]} == 0)); then
    mapfile -t versions < <(printf '%s\n' "${!sha256[@]}" | sort -V)
fi

mkdir -p "$cache"
failed=0
for v in "${versions[@]}"; do
    [[ -n "${sha256[$v]:-}" ]] || {
        echo "no pinned checksum for bash $v" >&2
        exit 2
    }
    bin="$cache/bash-$v/bin/bash"
    if [[ ! -x "$bin" ]]; then
        tgz="$cache/bash-$v.tar.gz"
        [[ -f "$tgz" ]] || curl -sSfL --retry 4 -o "$tgz" "https://ftp.gnu.org/gnu/bash/bash-$v.tar.gz"
        printf '%s  %s\n' "${sha256[$v]}" "$tgz" | sha256sum -c --quiet
        src=$(mktemp -d)
        tar -xzf "$tgz" -C "$src"
        (
            cd "$src/bash-$v"
            # Old releases predate C23 defaults; keep the compiler permissive.
            cflags="-O1 -std=gnu99 -Wno-error"
            if [[ "$v" == 3.* ]]; then
                cflags="-O1 -std=gnu89 -Wno-error -Wno-implicit-function-declaration -Wno-implicit-int -Wno-int-conversion -Wno-incompatible-pointer-types"
            fi
            CFLAGS="$cflags" ./configure --prefix="$cache/bash-$v" \
                --without-bash-malloc --disable-nls >/dev/null
            make -j"$(nproc)" >/dev/null 2>&1
            make install >/dev/null 2>&1
        )
        rm -rf "$src"
    fi
    if [[ "$v" == 3.* ]]; then
        # Unsupported (macOS default): must refuse cleanly with exit 4, both
        # when run and when sourced, before doing anything.
        rc=0
        out=$("$bin" "$here/../usb-audio-mapper.sh" --list 2>&1) || rc=$?
        # shellcheck disable=SC2016  # expanded by the child shell
        src=$("$bin" -c 'source "$1"; echo "still-running rc=$?"' _ "$here/../usb-audio-mapper.sh" 2>&1) || true
        if [[ $rc -eq 4 && "$out" == *"bash 4.0 or newer is required"* && "$src" == *"still-running rc=4"* ]]; then
            echo "bash $v: PASS (refuses with exit 4)"
        else
            echo "bash $v: FAIL (rc=$rc out=[$out] sourced=[$src])"
            failed=1
        fi
        continue
    fi
    if out=$(MAPPER_BASH="$bin" bats "$here" 2>&1); then
        echo "bash $v: PASS ($(grep -c '^ok' <<<"$out") tests)"
    else
        echo "bash $v: FAIL"
        grep -A8 '^not ok' <<<"$out" | head -40
        failed=1
    fi
done
exit "$failed"
