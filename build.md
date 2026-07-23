# RoohaniyeNoorIlmLinux — Build & Rebuild Guide

This document covers the full workflow for rebuilding the ISO after you edit
`roohaniye-shell` (the Qt/QML app in `shell-src/`). Keep this file in the
project root and update it if paths change.

> **⚠️ Read this first:** `live-build/build.sh` (run with `sudo`) is the
> real, current, day-to-day build path — see Section A. It has grown well
> beyond a simple squashfs/ISO repack: it also idempotently installs any
> package the chroot turns out to be missing (`cryptsetup`, `openssh-server`,
> `udisks2`, `rfkill`/`iw`, `wpasupplicant`, ...), (re)creates the
> `roohaniye` user/groups if they're ever missing, installs/enables all the
> project's systemd units, and masks known-bad units
> (`casper-md5check.service`). **The display stack is also no longer
> X11/lightdm/openbox** — it's direct `eglfs` on `tty1` via
> `roohaniye-shell.service`. Sections A–D and the package list in Section E
> below describe an earlier X11/lightdm architecture and are kept for
> historical/disaster-recovery reference, but for normal work **just run
> `build.sh`** and read its own comments (`live-build/build.sh`) for the
> authoritative, up-to-date list of what a build actually does — the script
> itself is more current than the prose below it in several places. Section
> G (bottom of this file) covers packaging custom drivers/firmware, which
> follows the same idempotent pattern as the script's package installs.

## Directory layout (reference)

```
~/Downloads/RoohaniyeNoorIlmLinux/
├── shell-src/                  # Qt/QML source
│   └── build/                  # CMake build dir — roohaniye-shell binary lives here
├── quran_text.db                # staged into chroot at /opt/roohaniye/data/
├── hadiths.db                   # staged into chroot at /opt/roohaniye/data/
└── live-build/
    ├── chroot/                  # the live filesystem tree (becomes the squashfs)
    │   ├── opt/roohaniye/bin/roohaniye-shell       # compiled binary lives here
    │   ├── opt/roohaniye/bin/start-shell.sh        # X session launcher script
    │   ├── opt/roohaniye/bin/openbox-rc.xml        # kiosk WM config
    │   ├── opt/roohaniye/data/*.db                 # runtime databases
    │   ├── usr/share/xsessions/roohaniye.desktop   # lightdm session entry
    │   ├── etc/lightdm/lightdm.conf.d/50-roohaniye-autologin.conf
    │   └── binary/casper/                          # ISO staging area
    │       ├── vmlinuz, initrd.img (symlinks)
    │       ├── filesystem.squashfs
    │       ├── filesystem.manifest
    │       └── filesystem.size
    └── chroot/boot/grub/grub.cfg    # GRUB menu (copied from efi.img originally)
```

---

## A. Quick rebuild — you only changed Qt/QML source, nothing else

Use this path for normal day-to-day work: you edited a `.cpp`/`.h`/`.qml`
file and want a fresh ISO to test.

**As of this writing, all six steps below are wrapped into one script:**
`live-build/build.sh` (run with `sudo`). It rebuilds the binary, checks
for missing shared libs, stages databases into the chroot, rebuilds the
squashfs, and rebuilds the ISO with an auto-incrementing `vgrubN` name -
same steps as documented here, just scripted. Flags control which
databases get staged beyond the always-included `quran_text.db` +
`hadiths.db`:

```bash
cd ~/Downloads/RoohaniyeNoorIlmLinux/live-build
sudo bash build.sh                       # base only (small ISO)
sudo bash build.sh --include-quran-audio # + quran_audio.db (~21GB)
sudo bash build.sh --include-mushaf      # + mushafs.db (~5.4GB, full-page scans)
sudo bash build.sh --include-all         # both of the above
```

`quran_audio.db` and `mushafs.db` are sourced from `/opt/roohaniye/data/`
on the dev machine (not from the project root - the project root only
carries the small `quran_text.db`/`hadiths.db` plus the deprecated,
unused `quran_audio_embedded.db`). The manual steps below are still the
reference for what the script does and for troubleshooting if it fails
partway through.

### 1. Rebuild the binary

```bash
cd ~/Downloads/RoohaniyeNoorIlmLinux/shell-src/build
cmake --build . --target roohaniye-shell -j$(nproc)
```

Confirm it ends with `[100%] Built target roohaniye-shell` and no errors.

### 2. (Optional but recommended) Smoke-test the binary before repacking

Catches crashes/missing-library issues before you spend time on a full
squashfs+ISO rebuild.

```bash
cd ~/Downloads/RoohaniyeNoorIlmLinux/live-build
sudo mount --bind /dev chroot/dev
sudo mount --bind /proc chroot/proc
sudo mount --bind /sys chroot/sys

# quick dependency check
sudo chroot chroot ldd /opt/roohaniye/bin/roohaniye-shell | grep "not found"
# (should print nothing)

# install xvfb temporarily if you want a headless run test
sudo chroot chroot /bin/bash -c "export DEBIAN_FRONTEND=noninteractive && apt-get install -y xvfb"
sudo chroot chroot /bin/bash -c "
  cd /opt/roohaniye/bin &&
  xvfb-run -a -s '-screen 0 1024x768x24' ./roohaniye-shell 2>&1 | head -60
"
# Ctrl+C after a few seconds once you see 'openDatabases: quranOk= true hadithOk= true'
# with no fatal errors, then remove xvfb again:
sudo chroot chroot /bin/bash -c "apt-get purge -y xvfb"

sudo umount chroot/dev chroot/proc chroot/sys
```

### 3. Copy the new binary into the chroot

```bash
cd ~/Downloads/RoohaniyeNoorIlmLinux/live-build
sudo cp ~/Downloads/RoohaniyeNoorIlmLinux/shell-src/build/roohaniye-shell \
  chroot/opt/roohaniye/bin/roohaniye-shell
sudo chmod +x chroot/opt/roohaniye/bin/roohaniye-shell
```

### 4. Rebuild the squashfs + manifest + size

```bash
cd ~/Downloads/RoohaniyeNoorIlmLinux/live-build

sudo rm -f chroot/binary/casper/filesystem.squashfs
sudo mksquashfs chroot chroot/binary/casper/filesystem.squashfs \
  -e boot -noappend -comp xz

sudo chroot chroot dpkg-query -W --showformat='${Package} ${Version}\n' \
  | sudo tee chroot/binary/casper/filesystem.manifest > /dev/null

printf $(sudo du -sx --block-size=1 chroot | cut -f1) \
  | sudo tee chroot/binary/casper/filesystem.size > /dev/null
```

### 5. Rebuild the ISO

Bump the version number in the filename each time so you don't confuse
builds (`grub14`, `grub15`, ...).

```bash
cd ~/Downloads/RoohaniyeNoorIlmLinux/live-build
sudo grub-mkrescue -volid ROOHANIYE -o RoohaniyeNoorIlm-vNEXT.iso chroot/binary/
sudo chown $USER:$USER RoohaniyeNoorIlm-vNEXT.iso
```

### 6. Boot-test in QEMU

```bash
pkill -f qemu-system-x86_64
sleep 1
qemu-system-x86_64 \
  -m 2048 \
  -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd \
  -drive if=pflash,format=raw,file=/tmp/OVMF_VARS.fd \
  -drive file=RoohaniyeNoorIlm-vNEXT.iso,format=raw,media=cdrom \
  -boot menu=on \
  -audiodev pa,id=snd0 \
  -device intel-hda \
  -device hda-duplex,audiodev=snd0 \
  -display gtk
```

(If `/tmp/OVMF_VARS.fd` is missing after a reboot, recreate it first:
`cp /usr/share/OVMF/OVMF_VARS_4M.fd /tmp/OVMF_VARS.fd`)

---

## B. Adding a new dependency (new Qt module, new library, etc.)

If your source change pulls in a new Qt module or system library, install it
in the chroot **before** rebuilding the squashfs:

```bash
cd ~/Downloads/RoohaniyeNoorIlmLinux/live-build
sudo mount --bind /dev chroot/dev
sudo mount --bind /proc chroot/proc
sudo mount --bind /sys chroot/sys

sudo chroot chroot /bin/bash -c "
  export DEBIAN_FRONTEND=noninteractive &&
  apt-get install -y --no-install-recommends <package-name>
"

sudo umount chroot/dev chroot/proc chroot/sys
```

Then continue with steps 3–6 above (copy binary, rebuild squashfs, rebuild
ISO, test).

**Tip:** after rebuilding the binary, check for missing libs before
repacking anything:

```bash
sudo mount --bind /dev chroot/dev; sudo mount --bind /proc chroot/proc; sudo mount --bind /sys chroot/sys
sudo chroot chroot ldd /opt/roohaniye/bin/roohaniye-shell | grep "not found"
sudo umount chroot/dev chroot/proc chroot/sys
```

Anything listed there needs its providing package installed in the chroot.

---

## C. Adding/updating a database or asset file

Databases are staged at fixed paths the app expects — currently:

- `/opt/roohaniye/data/quran_text.db`
- `/opt/roohaniye/data/hadiths.db`

To update one:

```bash
cd ~/Downloads/RoohaniyeNoorIlmLinux/live-build
sudo cp ~/Downloads/RoohaniyeNoorIlmLinux/quran_text.db chroot/opt/roohaniye/data/
sudo cp ~/Downloads/RoohaniyeNoorIlmLinux/hadiths.db    chroot/opt/roohaniye/data/
```

Then continue with steps 4–6 (squashfs rebuild → ISO rebuild → test). No
binary rebuild needed if only data changed.

---

## D. Full clean rebuild (rarely needed)

Only needed if the chroot itself gets corrupted or you want to start the
filesystem tree fresh. Not part of normal Qt-edit workflow — skip this
unless something is broken at the OS level, not the app level.

---

## E. Known-good package stack (for reference / disaster recovery)

If you ever need to rebuild the chroot from scratch, these are the packages
this build depends on, in the order they were added:

```bash
# live-boot essentials
apt-get install -y casper

# user account
adduser --disabled-password --gecos '' ubuntu
usermod -aG sudo,adm,cdrom,dip,plugdev ubuntu
echo 'ubuntu:ubuntu' | chpasswd

# desktop session bits (XFCE kept installed as unused fallback capability)
apt-get install -y --no-install-recommends xfce4 xfce4-goodies \
  lightdm lightdm-gtk-greeter network-manager network-manager-gnome
apt-get install -y accountsservice
apt-get install -y xserver-xorg xserver-xorg-video-all xserver-xorg-input-all
apt-get install -y --no-install-recommends openbox

# Qt5/QML runtime for roohaniye-shell
apt-get install -y --no-install-recommends \
  libqt5core5a libqt5gui5 libqt5qml5 libqt5quick5 libqt5quickwidgets5 \
  libqt5sql5 libqt5sql5-sqlite libqt5network5 libqt5multimedia5 \
  libqt5multimedia5-plugins \
  qml-module-qtquick2 qml-module-qtquick-controls2 qml-module-qtquick-layouts \
  qml-module-qtqml-models2 qml-module-qtmultimedia qml-module-qtgraphicaleffects \
  libgl1-mesa-dri libglx-mesa0 mesa-utils libpulse0

# audio
apt-get install -y --no-install-recommends pulseaudio
apt-get install -y --no-install-recommends alsa-utils alsa-base rtkit
```

Config files to recreate if starting fresh:

- `chroot/usr/share/xsessions/roohaniye.desktop` — defines the "RoohaniyeNoorIlm" session for lightdm
- `chroot/opt/roohaniye/bin/start-shell.sh` — launches openbox then execs the app
- `chroot/opt/roohaniye/bin/openbox-rc.xml` — decorationless/fullscreen-enforcing WM config
- `chroot/etc/lightdm/lightdm.conf.d/50-roohaniye-autologin.conf` — autologin `ubuntu` into the `roohaniye` session

Also ensure `chroot/etc/casper.conf` has `USERNAME="ubuntu"`, and
`chroot/boot/grub/grub.cfg` references `/casper/vmlinuz` /
`/casper/initrd.img` with a `search --label ROOHANIYE` line matching the
`-volid ROOHANIYE` used at ISO build time.

---

## F. Checklist before calling a build "done"

- [ ] Binary rebuilt from latest source (`cmake --build .`)
- [ ] `ldd ... | grep "not found"` is empty
- [ ] Squashfs rebuilt, manifest/size regenerated
- [ ] ISO rebuilt with `grub-mkrescue -volid ROOHANIYE`
- [ ] Boots to your app in QEMU (not tty1, not XFCE, not the small-window bug)
- [ ] Fullscreen fills the display, no gaps
- [ ] Audio plays (test in QEMU with `-audiodev pa ...`, then confirm on real hardware)
- [ ] Tested on real hardware, not just QEMU, before distributing
- [ ] ISO copied somewhere safe (this build directory is not a backup)

---

## G. Packaging custom drivers / firmware

This covers adding hardware support (touchscreen firmware, kernel modules,
udev rules, etc.) that needs to be baked into every future ISO — not a
one-off fix on a single already-booted device. The pattern below is exactly
what was used to add broad Silead touchscreen support; follow the same
shape for anything else.

### Where things live

- **`live-build/config-src/`** — source files that get copied into the
  chroot at build time. This is a real, git-tracked source directory (see
  the `.gitignore` note below) — put new driver/firmware files here, never
  directly in `live-build/chroot/` (that's throwaway build output).
- **`live-build/config-src/0100-setup-roohaniye.hook.chroot`** — the
  live-build hook script that runs *inside* the chroot the one time you do
  a from-scratch `lb build` (see Section E/D). It's also hand-mirrored by
  the equivalent steps in `build.sh`, since `build.sh` normally refreshes
  an *existing* chroot rather than bootstrapping a new one — **if you add
  something to the hook script, add the matching step to `build.sh` too**,
  or it'll only apply the next time someone does a full from-scratch
  rebuild, not on normal `sudo bash build.sh` runs.
- **`live-build/config-src/<name>-firmware/`** — a subdirectory per driver
  bundle (see the `silead-firmware/` example, ~70 files, one per supported
  device/panel).

### Steps to add a new firmware/driver bundle

1. **Drop the firmware/driver files into `config-src/`.** Prefer storing
   the actual files in the repo (`config-src/<name>-firmware/*.fw` etc.)
   over fetching them at build time — this keeps builds working offline
   and not dependent on a third-party site being reachable mid-build.

2. **Add the install step to `0100-setup-roohaniye.hook.chroot`** (for
   from-scratch builds) — copy files to their real destination under
   `/lib/firmware/<driver>/`, `/lib/modules/...`, `/etc/udev/rules.d/`,
   etc., whatever the driver in question expects. Comment *why* — which
   symptom this fixes, what hardware it was diagnosed on, and any
   filename/path quirks (e.g. some kernels/DMI-quirk revisions request a
   firmware file under a different name than the vendor's own filename —
   installing under both names is often the simplest fix rather than
   tracking exactly which one a given kernel build wants).

3. **Mirror the same install step in `build.sh`**, following its existing
   idempotent-install pattern (check if it's already present/missing,
   only act if needed, log what happened) — see the `cryptsetup`/
   `udisks2`/`rfkill` blocks in `build.sh` for the template to copy.

4. **If a kernel module needs to be forced to load** (rather than relying
   on auto-bind via ACPI/PCI ID, which is what most drivers do and needs
   nothing extra), add it to `/etc/modules-load.d/` in the chroot rather
   than a manual `modprobe` step — that's the standard systemd-native way
   to guarantee a module loads at every boot.

5. **If a *service* is found to hang boot indefinitely** (as happened with
   `rsyslog.service` and `apport.service` on this hardware — both stall
   with no timeout on certain boards) — the fix is `systemctl mask
   <service>` in both the hook script and `build.sh`, not a driver/firmware
   fix. Comment why it was masked, since masking is otherwise a stealthy
   change that's easy to forget the reason for later.

6. **Track it in git.** `live-build/` is gitignored as build output, but
   `config-src/` is explicitly re-included via a negation pattern in
   `.gitignore` (`live-build/*` + `!live-build/config-src/`) specifically
   so source files like driver bundles don't live *only* on the one
   machine that happened to add them. Run `git status --short
   --untracked-files=all live-build/config-src/` to confirm new files are
   actually visible to git before committing.

7. **Test with a real from-scratch chroot boot if possible**, not just
   `build.sh` against an already-fixed chroot — that's the only way to
   confirm the hook script (not just `build.sh`'s idempotent patch) is
   actually correct, since the hook path and the `build.sh` path can
   silently drift apart otherwise (see the warning at the top of this
   file about `roohaniye-shell.service` once being missing from a chroot
   that `build.sh` had been quietly patching around for a while).

### Diagnosing new hardware before packaging a fix

If you're chasing a *new* piece of unsupported hardware (not just
reapplying a known fix), the general diagnostic flow that worked for the
touchscreen case:

```bash
# Is the kernel driver even loaded?
lsmod | grep -iE "<driver-name>"
sudo modprobe <driver-name>; echo "exit: $?"

# Does the kernel see the device at all (ACPI-attached devices, e.g. I2C-HID touch controllers)?
ls /sys/bus/acpi/devices/ | grep -i <expected-ACPI-ID>

# For input devices specifically - is anything registering at the libinput level?
sudo libinput list-devices
sudo libinput debug-events   # then physically interact with the hardware

# What's the kernel actually saying about it?
sudo dmesg | grep -iE "<driver-name>|<device-name>"
```

A `Direct firmware load for <path> failed with error -2` in `dmesg` means
the driver bound and is talking to the chip, but the firmware file it's
asking for (check the exact path in that log line) isn't present — that's
almost always a firmware-packaging problem like this section covers, not a
deeper driver bug.
