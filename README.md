# RoohaniyeNoorIlm Linux

**A distraction-free Linux distribution built for reading the Qur'an and Hadith — anywhere, without your phone getting in the way.**

You know the moment: you open your phone to read a page of Qur'an, and a message notification pulls you somewhere else entirely. RoohaniyeNoorIlm Linux exists to remove that problem. It's a lightweight, kiosk-style OS with a custom-built interface — no notifications, no app-switching, no distractions — focused entirely on Qur'an, Hadith, and prayer.

It boots straight into its own custom shell (built with Qt/QML), not a general-purpose desktop, so there's nothing else competing for your attention.

---

## Features

- **Qur'an reader** — full text, organized by Surah and Juz, with a dedicated Hifz (memorization) section, reciter selection, "go to page" navigation, and an About Qur'an section
- **Mushaf reader** — scanned print-mushaf pages, viewed page by page, with pinch-to-zoom (touch), mouse-wheel/drag zoom and pan, and resume-last-page
- **Hadith reader** — Sahih al-Bukhari and Sahih Muslim, organized by topic
- **Prayer Times** — location-based prayer time display
- **Qibla direction** finder
- **Reminders** — for prayer, reading goals, etc.
- **App Center** — for browsing/installing additional apps within the OS
- **Installer Wizard** — guided setup when first installing the OS
- **Virtual Keyboard** — built in for touch-screen devices
- **Lock Screen**
- **Light/Dark theming**
- **Database Connector** — import your own `.db` content packs

Designed to run on **all hardware** — from modern laptops down to old, low-spec machines (tested successfully on a 2GB RAM / DDR3L tablet).

---

## Download

The full bootable `.iso` (including the Qur'an and Hadith databases) is available on the **[Releases](../../releases)** page.

- Works on **both Intel and AMD** 64-bit (x86_64) computers
- **Not** compatible with ARM devices (e.g. Raspberry Pi, ARM-based Chromebooks) in its current form

### Flashing to a USB drive

**⚠️ This will erase everything on the target USB drive. Double-check the device name before running any command.**

On Linux:
```bash
# 1. Identify your USB drive (look for the correct size/removable flag — NOT your internal disk)
lsblk

# 2. Unmount any auto-mounted partitions on it (replace sdX with your device)
sudo umount /dev/sdX1 /dev/sdX2 2>/dev/null

# 3. Write the ISO (replace sdX with your device, and the filename with your downloaded ISO)
sudo dd if=RoohaniyeNoorIlm.iso of=/dev/sdX bs=4M status=progress oflag=sync
sync
```

On Windows or macOS, use a tool such as [Rufus](https://rufus.ie/) (Windows) or [balenaEtcher](https://etcher.balena.io/) (cross-platform) to write the `.iso` to a USB drive.

Then boot your target machine from the USB (usually F2, F12, Esc, or Del at startup, depending on your hardware) and follow the on-screen Installer Wizard, or run it live directly from the USB.

---

## Building from Source

If you want to modify the shell or rebuild the OS yourself, see **[build.md](build.md)** for the full, step-by-step build and rebuild workflow, including:

- Compiling the Qt/QML shell
- Setting up the live-build chroot environment
- Packaging the squashfs and bootable ISO
- Testing in QEMU before flashing to real hardware

### Quick overview of the stack

- **Shell**: Qt5 / QML (`shell-src/`) — a custom kiosk application, not a general desktop environment
- **Base OS**: Ubuntu 24.04 LTS (Noble Numbat), built with `live-build` + `casper`
- **Display**: X11 + `openbox` (minimal window manager, enforces fullscreen kiosk mode) + `lightdm` (autologin, no login screen)
- **Audio**: PulseAudio over ALSA

### Repository layout

```
├── shell-src/          # Qt/QML source for the RoohaniyeNoorIlm shell
│   ├── qml/             # UI screens (Quran, Hadith, Prayer Times, Qibla, etc.)
│   ├── *backend.cpp/.h  # C++ backends (audio, database, prayer times, wifi, etc.)
│   └── CMakeLists.txt
├── assets/              # Shared UI/media assets
├── live-build/          # Live-build workspace (build output — not tracked in git)
├── build.md             # Full build & rebuild instructions
├── manifest.json
└── apps.json.example
```

> **Note:** `live-build/`, compiled binaries, `.iso` files, and the Qur'an/Hadith `.db` files are intentionally excluded from this repository via `.gitignore` — they're either regenerable build output or large data files distributed separately via [Releases](../../releases).

---

## Requirements to Build

- Ubuntu/Debian-based Linux host
- `live-build`, `debootstrap`, `xorriso`, `grub-pc-bin`, `grub-efi-amd64-bin`, `mtools`, `squashfs-tools`
- Qt5 development packages (`qtbase5-dev`, `qtdeclarative5-dev`, `qtmultimedia5-dev`, etc.) and CMake for building the shell itself
- QEMU + OVMF, for testing ISOs before flashing to real hardware

Full package list and step-by-step instructions are in [build.md](build.md).

---

## Contributing

Issues and pull requests are welcome — whether that's new Hadith collections, translations, bug fixes, UI improvements, or hardware compatibility fixes.

---

## License

This project is licensed under the **MIT License** — see [LICENSE](LICENSE) for details.

Copyright © 2026 OpenNoorIlm
