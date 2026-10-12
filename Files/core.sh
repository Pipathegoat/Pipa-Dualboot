# Shared logic for patch.sh and the recovery installer (POSIX sh).
# Caller provides: set_bin DIR (tool dir), WORK (scratch dir), PART, PSIZE,
#                  say MSG, fail MSG (must exit).  Patching also needs UEFI, CFG, SC.
# set_bin DIR -> point MB/KP/UR at the tool set in DIR
set_bin() { BIN="$1"; MB="$BIN/magiskboot"; KP="$BIN/DualBootKernelPatcher"; UR="$BIN/DualBootPatchRemover"; chmod +x "$MB" "$KP" "$UR" 2>/dev/null || true; }

fsize() { wc -c < "$1" | tr -d ' '; }

# kernel_state FILE -> patched | stock | unknown
# Patched = first two instructions are both "b" (0x14xxxxxx), same test the patcher uses.
kernel_state() {
  command -v od >/dev/null 2>&1 || { echo unknown; return; }
  ks_f="$1"; ks_o=0
  [ "$(head -c 16 "$ks_f" | tr -d '\000')" = UNCOMPRESSED_IMG ] && ks_o=20
  set -- $(od -An -tx1 -j "$ks_o" -N 8 "$ks_f")
  [ $# -eq 8 ] || { echo unknown; return; }
  if   [ "$4" = 14 ] && [ "$8" = 14 ]; then echo patched
  elif [ "$4" = 14 ] || [ "$1$2" = 4d5a ]; then echo stock
  else echo unknown; fi
}

# run a tool quietly, show the tail of its output on failure
quiet() { "$@" >"$WORK/log" 2>&1 && return 0; tail -n 4 "$WORK/log" | while IFS= read -r l; do say "   $l"; done; return 1; }

# write IMG to $PART and compare it back
write_verify() {
  dd if="$1" of="$PART" bs=1048576 conv=notrunc 2>/dev/null || return 1
  sync
  head -c "$(fsize "$1")" "$PART" | cmp -s - "$1"
}

# load_boot IMG  -> unpacks into $WORK, sets STATE (kernel state of that image)
load_boot() {
  cp "$1" "$WORK/boot.img" || fail "not enough space for the working copy"
  rm -f "$WORK/kernel"
  ( cd "$WORK" && quiet "$MB" unpack boot.img ) || fail "unpack failed - not a valid boot image"
  [ -s "$WORK/kernel" ] || fail "unpack produced no kernel"
  STATE="$(kernel_state "$WORK/kernel")"
  [ "$STATE" != unknown ] || fail "kernel format not recognised (no branch / EFI header)"
}

# build_img patch|unpatch -> $WORK/new.img ; checks the kernel before, after patching and after repacking
build_img() {
  cd "$WORK" || fail "cannot enter $WORK"
  if [ "$1" = patch ]; then
    KIN=kernel
    if [ "$STATE" = patched ]; then
      # The patcher's own re-patch path writes an empty file for kernels with an
      # UNCOMPRESSED_IMG header, so strip the old patch first and patch fresh.
      say "Kernel already patched - removing the old patch first"
      quiet "$UR" kernel kernel.stock && [ "$(kernel_state kernel.stock)" = stock ] || fail "could not strip the old patch"
      KIN=kernel.stock
    fi
    quiet "$KP" "$KIN" "$UEFI" kernel.new "$CFG" "$SC" || fail "patcher failed"
    want=patched
  else
    [ "$STATE" = patched ] || fail "kernel is not patched - nothing to remove"
    quiet "$UR" kernel kernel.new || fail "patch remover failed"
    want=stock
  fi
  [ -s kernel.new ] && [ "$(kernel_state kernel.new)" = "$want" ] || fail "patched kernel failed the $want check"
  mv -f kernel.new kernel
  quiet "$MB" repack boot.img new.img && [ -s new.img ] || fail "repack failed"
  # unpack the result again and confirm the kernel inside
  rm -rf chk; mkdir chk
  ( cd chk && quiet "$MB" unpack ../new.img ) && [ "$(kernel_state chk/kernel)" = "$want" ] \
    || fail "repacked image failed the $want check - nothing was written"
  rm -rf chk
  NSIZE="$(fsize new.img)"
  [ "$NSIZE" -le "$PSIZE" ] || fail "new image ($NSIZE bytes) does not fit the partition ($PSIZE bytes) - nothing was written"
}

# ---- helpers for patch.sh / patch_boot_a.sh (the recovery installer does not use these) ----

# init_env -> picks the tool set for this platform and creates the scratch dir ($B must be set)
#   bin/arm64 = Android/Termux, bin/aarch64 = Linux arm64, bin/x86_64 = Linux x86_64
init_env() {
  case "$(uname -m)" in
    aarch64|arm64) if [ "$(uname -o 2>/dev/null)" = Android ] || [ -e /system/bin/app_process ]; then ARCH=arm64; else ARCH=aarch64; fi ;;
    x86_64|amd64)  ARCH=x86_64 ;;
    *) fail "unsupported CPU $(uname -m)" ;;
  esac
  set_bin "$B/bin/$ARCH"; echo "Tools: bin/$ARCH"
  for d in "${TMPDIR:-}" /tmp /data/local/tmp "$B"; do   # first writable temp folder
    [ -n "$d" ] && [ -w "$d" ] && WORK="$(mktemp -d "$d/dualboot.XXXXXX" 2>/dev/null)" && break
  done
  [ -n "${WORK:-}" ] || fail "no writable temp folder"
  trap 'rm -rf "$WORK"' EXIT
}

# pick LABEL FILE... -> PICKED ; asks only when there is more than one file
#   if $PICK_DESC is a file, its line N describes the Nth file (alphabetical order)
pick() {
  pk_l="$1"; shift
  [ -e "$1" ] || fail "no $pk_l found"
  [ $# -eq 1 ] && { PICKED="$1"; return; }
  pk_i=1; for f in "$@"; do pk_d=""; [ -f "${PICK_DESC:-}" ] && pk_d="$(sed -n "${pk_i}p" "$PICK_DESC")"; echo "  $pk_i) $(basename "$f")${pk_d:+ - $pk_d}"; pk_i=$((pk_i + 1)); done
  printf 'Select %s [1-%s]: ' "$pk_l" $#; read -r pk_n || fail "no selection"
  case "$pk_n" in ''|*[!0-9]*) fail "invalid selection" ;; esac
  [ "$pk_n" -ge 1 ] && [ "$pk_n" -le $# ] || fail "invalid selection"
  eval "PICKED=\${$pk_n}"
}

# choose_inputs -> UEFI CFG SC (asks which UEFI / shell code if several; config is never asked)
choose_inputs() {
  pick UEFI "$B"/fd/*.fd;           UEFI="$PICKED"
  CFG="$(ls "$B"/cfg/*.cfg 2>/dev/null | head -n 1)"; [ -f "$CFG" ] || fail "no *.cfg in Files/cfg"
  PICK_DESC="$B/sc/description.txt" pick "shell code" "$B"/sc/*.bin;  SC="$PICKED"
  SS="$(sed -n 's/^StackSize=\(0x[0-9A-Fa-f]*\).*/\1/p' "$CFG" | head -n 1)"
  [ -z "$SS" ] || [ "$(fsize "$UEFI")" -le $((SS)) ] || fail "UEFI is larger than StackSize $SS"
  say "UEFI: $(basename "$UEFI")   Shell code: $(basename "$SC")"
}
