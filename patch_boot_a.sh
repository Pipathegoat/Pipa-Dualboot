#!/bin/sh
# Pipa dual boot: patch (or unpatch) the boot_a partition on the tablet. Needs root.
#   ./patch_boot_a.sh [-u]       (-u = remove the patch)
# Assumes Linux is running from slot b; boot_a is the Android slot.
# On Android run it as:  su -c "sh /path/patch_boot_a.sh"
set -eu
B="$(cd "$(dirname "$0")" && pwd)/Files"
say()  { echo "$*"; }
fail() { echo "ERROR: $*" >&2; exit 1; }

MODE=patch; [ "${1:-}" = -u ] && { MODE=unpatch; shift; }
. "$B/core.sh"; init_env

PART=""      # Linux and Android keep partition names in different places
for d in /dev/disk/by-partlabel /dev/block/by-name /dev/block/bootdevice/by-name; do [ -e "$d/boot_a" ] && PART="$d/boot_a" && break; done
[ -n "$PART" ] || fail "boot_a not found (run as root)"
[ -e "$PART" ] || fail "$PART not found"
PART="$(readlink -f "$PART")"
[ -r "$PART" ] && [ -w "$PART" ] || fail "no read/write access to $PART - run as root"
if [ -b "$PART" ]; then
  PSIZE="$(blockdev --getsize64 "$PART" 2>/dev/null)" || PSIZE=$(( $(cat "/sys/class/block/$(basename "$PART")/size") * 512 ))
else PSIZE="$(fsize "$PART")"; fi
grep -q "^$PART " /proc/mounts 2>/dev/null && fail "$PART is mounted"
say "Partition: $PART ($PSIZE bytes)"

BK="$B/backups"; mkdir -p "$BK" 2>/dev/null && [ -w "$BK" ] || fail "cannot write to $BK"
BACKUP="$BK/$(basename "$PART")-$(date +%Y%m%d-%H%M%S).img"
dd if="$PART" of="$BACKUP" bs=1048576 2>/dev/null
[ "$(fsize "$BACKUP")" -eq "$PSIZE" ] || fail "backup incomplete, nothing changed"
say "Backup: $BACKUP"

load_boot "$BACKUP"
say "Kernel in $PART: $STATE"
[ "$MODE" = patch ] && choose_inputs
build_img "$MODE"
say "$MODE OK: new image $NSIZE bytes, kernel check passed"

printf 'About to overwrite %s. Type YES: ' "$PART"; read -r a || a=""; [ "$a" = YES ] || fail "aborted, nothing written"
if write_verify "$WORK/new.img"; then say "Written and verified."
else say "Verify failed - restoring backup"; write_verify "$BACKUP" || fail "RESTORE FAILED: dd if=$BACKUP of=$PART bs=1M"; fail "write failed, original restored"; fi
say "Undo: dd if=$BACKUP of=$PART bs=1M conv=fsync"
