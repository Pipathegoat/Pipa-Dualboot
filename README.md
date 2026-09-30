# Pipa DualBoot

Run **Android and Linux on the Xiaomi Pad 6 (Pipa)** and pick which one starts at power-on, without touching any buttons.

## What is this?

This project patches the Android boot image (the `boot_a` kernel). At power-on, the patch checks one condition:

- if it matches, the tablet starts the **UEFI**, and from there you boot **Linux**
- if not, **Android** boots normally

You choose the condition (a **shell code**): the magnetic cover, or the screen orientation.

> The scripts were written with an LLM. Use with caution. Every method below makes a backup or leaves your original file untouched, but you still need a way to get back to a working Android (see [Undo](#undo)).

## What you need

- Xiaomi Pad 6 (Pipa) with an **unlocked bootloader**
- The **stock boot image of your Android ROM** (`boot.img`), or root / a recovery on the tablet
- Linux set up for the tablet (example: [docs/embedded-grub.md](docs/embedded-grub.md))

## Choose a shell code

| Shell code | Boots Linux when | Otherwise |
|---|---|---|
| `Pipa.Magnetic.cover` | magnetic cover is closed | Android |
| `Pipa.Orientation` | tablet is in inverted landscape at boot | Android |

The script lists them and asks you to pick one by number. The descriptions it shows come from `Files/sc/description.txt` (one line per shell code, alphabetical order).

## 3 ways to patch

Pick **one**. Download this repo first (**Code → Download ZIP**) and extract it.

### Option 1: Patch a boot image file (no root)

Easiest. Works in Termux on the tablet, or on any Linux PC. Your original file is not changed.

1. Put the stock `boot.img` in the repo folder.
2. Run:
   ```sh
   sh patch.sh boot.img
   ```
3. Choose a shell code when asked. The result is **`boot-repack.img`**.
4. Flash it to the Android slot:
   ```sh
   fastboot flash boot_a boot-repack.img
   ```

Termux tips: run `termux-setup-storage` once to reach your files, copy the repo and `boot.img` into your **home folder** (not `/sdcard`), and run the script from there.

### Option 2: Patch the partition directly (root, from Linux)

For when Linux is already running on the tablet. **Linux must be running from slot b**: the script patches `boot_a`, the Android slot. Never run it while booted from slot a.

```sh
sudo sh patch_boot_a.sh
```

It backs up `boot_a` to `Files/backups/`, builds and checks the new image, asks you to type `YES`, writes it and verifies. If the check fails, it puts the backup back by itself.

### Option 3: Flash in recovery (TWRP etc.)

1. Zip the **contents** of this repo, so `META-INF` is at the top of the zip and not inside a folder.
2. Flash the zip in recovery.
3. Use **Vol Down** to go to the next option (1, 2, 3, 4, then back to 1) and **Vol Up** to select the highlighted one. Choose *Patch boot*, then the slot (`boot_a`), then a shell code.

The menu can also remove the patch or restore a backup (backups are in `/sdcard/DualBoot/backups`).

## Remove the patch

Use the same method with `-u`:
```sh
sh patch.sh -u boot.img          # option 1
sudo sh patch_boot_a.sh -u       # option 2
```
In recovery (option 3), choose *Remove patch*.

## Undo

Flash the stock boot image of your ROM.

## Credits and acknowledgments

| Project | Used for |
|---|---|
| [Mu-Silicium](https://github.com/Project-Silicium/Mu-Silicium) | UEFI |
| [DualBootKernelPatcher](https://github.com/Project-Aloha/DualBootKernelPatcher) (Project-Aloha) | Dual boot patcher, and the Magnetic cover shell code |
| [Magisk](https://github.com/topjohnwu/Magisk) (topjohnwu) | `magiskboot` |
| [magiskboot-linux](https://github.com/Uevo001/magiskboot-linux) (Uevo001) | Prebuilt `magiskboot` |
| [Stelle](https://github.com/Danial-Movahed/) | Digging up this possibility, and the reason I came across it |

## Reproducible UEFI image

Source to reproduce the Mu-Silicium UEFI image: [Pipathegoat/Mu-Silicium](https://github.com/Pipathegoat/Mu-Silicium)
