# RoohaniyeNoorIlmLinux — Build & Rebuild Guide

This document covers the full workflow for rebuilding the ISO after you edit
`roohaniye-shell` (the Qt/QML app in `shell-src/`). Keep this file in the
project root and update it if paths change.

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
