# Example: boot Linux from UEFI with an embedded GRUB

Only an example. Any loader that ends up at `EFI/BOOT/BOOTAA64.EFI` on the ESP works; adapt it to your distro.

> **Erasing `userdata` removes all your files in Android.** Back up first.

## Create the ESP
Use GParted to erase the `userdata` partition. Then create it again with the name `userdata`, and add a new **280MB FAT32 partition named `esp`** (set the `esp` flag). Then mount it:
```bash
mkdir -p /boot/efi
mount /dev/disk/by-partlabel/esp /boot/efi
mkdir -p /boot/efi/EFI/BOOT
```

## Build the embedded GRUB
Save this as `build-grub.sh`:
```bash
#!/bin/bash
set -e

SRC=/boot
DTB=/boot/dtbs/qcom/sm8250-xiaomi-pipa.dtb
FONT=/usr/share/grub/unicode.pf2
OUT=/boot/efi/EFI/BOOT/BOOTAA64.EFI
CFG=$(mktemp)

for f in "$SRC/Image" "$SRC/initramfs.img" "$DTB" "$FONT"; do
  [ -f "$f" ] || { echo "Missing $f"; exit 1; }
done

cat > "$CFG" <<'EOF'
insmod all_video
insmod efi_gop
insmod font
insmod gfxterm
loadfont (memdisk)/boot/grub/fonts/unicode.pf2
set gfxmode=auto
set gfxpayload=keep
terminal_output gfxterm

set timeout=3
set default=0

menuentry "Artix (Embedded)" {
    devicetree (memdisk)/boot/pipa/sm8250-xiaomi-pipa.dtb
    linux (memdisk)/boot/pipa/Image root=LABEL=armtix rootwait rw loglevel=7 console=tty0 earlycon=tty0 keep_bootcon fbcon=rotate:1,font:VGA8x16
    initrd (memdisk)/boot/pipa/initramfs.img
}
EOF

grub-mkstandalone -O arm64-efi \
  -o "$OUT" \
  --install-modules="normal linux fdt font all_video efi_gop gfxterm part_gpt fat ext2 echo" \
  "boot/grub/grub.cfg=$CFG" \
  "boot/grub/fonts/unicode.pf2=$FONT" \
  "boot/pipa/Image=$SRC/Image" \
  "boot/pipa/initramfs.img=$SRC/initramfs.img" \
  "boot/pipa/sm8250-xiaomi-pipa.dtb=$DTB"

rm -f "$CFG"
sync
ls -lh "$OUT"
```
Run it with `sudo bash build-grub.sh`. No separate `grub-install` is needed, because the script writes the loader to `EFI/BOOT/BOOTAA64.EFI`, the path the firmware looks for.

Notes:
- The result is one EFI file of about 40MB or more, holding the kernel, initramfs, DTB, and font.
- If the DTB isn't found, check with `ls /boot/dtbs/qcom/ | grep pipa`.
- If `grub-mkstandalone` complains about a missing module, make sure `fdt` is in `--install-modules`.
- Squares in the menu mean the font is missing. The `unicode.pf2` graft point prevents that.
- Change `root=LABEL=armtix` to your own root label.
- Everything is baked into `BOOTAA64.EFI`, so rerun `build-grub.sh` after every kernel, initramfs, or DTB update. A pacman hook can automate this.

