#!/bin/sh
# Pipa dual boot: patch (or unpatch) a boot IMAGE FILE. No root needed; the input is never modified.
#   ./patch.sh [-u] [boot.img]   ->  ./boot-repack.img
#   -u  remove the patch.   (to patch the boot_a partition on the tablet use patch_boot_a.sh)
set -eu
B="$(cd "$(dirname "$0")" && pwd)/Files"
say()  { echo "$*"; }
fail() { echo "ERROR: $*" >&2; exit 1; }

MODE=patch; [ "${1:-}" = -u ] && { MODE=unpatch; shift; }
IN="${1:-boot.img}"; OUT="$(pwd)/boot-repack.img"
. "$B/core.sh"; init_env
[ -f "$IN" ] && [ -r "$IN" ] || fail "cannot read $IN"
[ "$IN" -ef "$OUT" ] && fail "input and output are the same file - run from another folder"
PSIZE=999999999999            # size of the original partition is unknown for a plain file

load_boot "$IN"
say "Kernel in $IN: $STATE"
[ "$MODE" = patch ] && choose_inputs
build_img "$MODE"
cp "$WORK/new.img" "$OUT" || fail "cannot write $OUT"
say "$MODE OK, kernel check passed: $OUT ($NSIZE bytes)"
