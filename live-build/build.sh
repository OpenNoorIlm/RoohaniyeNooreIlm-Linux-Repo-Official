#!/bin/bash
# Rebuilds the RoohaniyeNoorIlm .iso from the already-set-up chroot at
# live-build/chroot/, following the manual workflow documented in
# build.md (Sections A + C) - NOT `lb config`/`lb build` from scratch.
# That means this script assumes the chroot already has its base OS and
# systemd units in place (build.md Section E covers rebuilding that from
# nothing; it's rare and not part of this script - NOTE Section E's
# package list describes an old X11/lightdm/openbox architecture this
# project no longer uses; the shell now runs directly on eglfs via
# roohaniye-shell.service, see build.md's top-of-file warning). What this script actually redoes every run:
#   1. rebuild the roohaniye-shell binary from shell-src/
#   2. copy that binary + the requested databases into chroot/
#   3. rebuild filesystem.squashfs (+ manifest/size)
#   4. rebuild the .iso with grub-mkrescue
#
# Must be run with sudo (chroot/mksquashfs/grub-mkrescue all need root -
# same reason live-build/README.md gives for why Claude can't run this
# part itself: sudo here needs an interactive password prompt).
#
# Data flags (combinable, e.g. `sudo bash build.sh --include-all`):
#
#   sudo bash build.sh
#     Base build: quran_text.db + hadiths.db only (matches build.md
#     Section C's currently-staged set). Small ISO. Quran audio and
#     the full-page Mushaf scans aren't included; audio can still be
#     imported later via Database Connector.
#
#   sudo bash build.sh --include-quran-audio
#     Also stages quran_audio.db (~21GB, all 9 reciters). Located by
#     filename alone via find_db() below - checks the project root and
#     /opt/roohaniye/data first, then falls back to searching your home
#     dir, so you never need to type/remember its actual path. NOT the
#     same file as quran_audio_embedded.db in the project root, which is
#     the deprecated pre-split file and is never used here.
#
#   sudo bash build.sh --include-mushaf
#     Also stages mushafs.db (~5.4GB, full-page scans for all printed/
#     hafizi mushaf editions). Located by filename the same way.
#
#   sudo bash build.sh --include-all
#     Both of the above, on top of the base databases. Largest ISO.
#
# Output filename: RoohaniyeNoorIlm-vgrubN-<variant>.iso, where N
# auto-increments from whatever's already in live-build/ (matches the
# "bump the version each time" convention build.md asks for) and
# <variant> is base / audio / mushaf / full depending on the flags.

set -e

INCLUDE_AUDIO=0
INCLUDE_MUSHAF=0
for arg in "$@"; do
    case "$arg" in
        --include-quran-audio) INCLUDE_AUDIO=1 ;;
        --include-mushaf) INCLUDE_MUSHAF=1 ;;
        --include-all) INCLUDE_AUDIO=1; INCLUDE_MUSHAF=1 ;;
        *)
            echo "Unknown option: $arg (expected --include-quran-audio, --include-mushaf, --include-all)" >&2
            exit 1
            ;;
    esac
done

if [ "$INCLUDE_AUDIO" -eq 1 ] && [ "$INCLUDE_MUSHAF" -eq 1 ]; then
    VARIANT="full"
elif [ "$INCLUDE_AUDIO" -eq 1 ]; then
    VARIANT="audio"
elif [ "$INCLUDE_MUSHAF" -eq 1 ]; then
    VARIANT="mushaf"
else
    VARIANT="base"
fi
echo "== Building variant: $VARIANT =="

if [ "$(id -u)" -ne 0 ]; then
    echo "Run this with sudo: sudo bash build.sh [--include-quran-audio] [--include-mushaf] [--include-all]" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHROOT="$SCRIPT_DIR/chroot"
SHELL_BUILD_DIR="$PROJECT_ROOT/shell-src/build"
SHELL_BIN="$SHELL_BUILD_DIR/roohaniye-shell"
REAL_USER="${SUDO_USER:-$(id -un)}"
REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"

# Locate a database by filename alone - checks the fast/known spots first
# (project root, /opt/roohaniye/data), then falls back to a search under
# the real user's home dir. Means you never have to remember or type
# where a .db actually lives, just its name.
find_db() {
    local name="$1"
    local candidates=("$PROJECT_ROOT/$name" "/opt/roohaniye/data/$name")
    for c in "${candidates[@]}"; do
        [ -f "$c" ] && { echo "$c"; return 0; }
    done
    local found
    found="$(find "$REAL_HOME" -maxdepth 6 -iname "$name" -type f 2>/dev/null | head -n1)"
    if [ -n "$found" ]; then
        echo "$found"
        return 0
    fi
    return 1
}

if [ ! -d "$CHROOT" ]; then
    echo "ERROR: $CHROOT not found. This script only refreshes an existing" >&2
    echo "chroot (build.md Section A/C) - it doesn't bootstrap one from" >&2
    echo "scratch. See build.md Section D/E for that." >&2
    exit 1
fi

echo "== 1. Rebuilding roohaniye-shell =="
if [ ! -d "$SHELL_BUILD_DIR" ]; then
    echo "ERROR: $SHELL_BUILD_DIR not found - run the initial cmake configure first." >&2
    exit 1
fi
sudo -u "$REAL_USER" cmake --build "$SHELL_BUILD_DIR" --target roohaniye-shell -j"$(nproc)"
if [ ! -x "$SHELL_BIN" ]; then
    echo "ERROR: build finished but $SHELL_BIN is missing/not executable." >&2
    exit 1
fi

echo "== Sanity-checking requested database files exist before we start =="
QURAN_TEXT_DB="$(find_db quran_text.db)" || { echo "ERROR: quran_text.db not found anywhere under $REAL_HOME." >&2; exit 1; }
HADITHS_DB="$(find_db hadiths.db)" || { echo "ERROR: hadiths.db not found anywhere under $REAL_HOME." >&2; exit 1; }
echo "   quran_text.db -> $QURAN_TEXT_DB"
echo "   hadiths.db    -> $HADITHS_DB"

if [ "$INCLUDE_AUDIO" -eq 1 ]; then
    QURAN_AUDIO_DB="$(find_db quran_audio.db)" || { echo "ERROR: quran_audio.db not found anywhere under $REAL_HOME." >&2; exit 1; }
    echo "   quran_audio.db -> $QURAN_AUDIO_DB"
fi
if [ "$INCLUDE_MUSHAF" -eq 1 ]; then
    MUSHAFS_DB="$(find_db mushafs.db)" || { echo "ERROR: mushafs.db not found anywhere under $REAL_HOME." >&2; exit 1; }
    echo "   mushafs.db -> $MUSHAFS_DB"
fi

echo "== 2. Checking for missing shared libraries (build.md Section A step 2 / B tip) =="
# Defensive cleanup: if a previous run crashed/was interrupted before its
# own umount below, dev/proc/sys can be left mounted (possibly stacked
# multiple times). Clear any stale mounts before mounting fresh, so this
# can never accumulate across runs.
for d in proc sys dev; do
    while mountpoint -q "$CHROOT/$d" 2>/dev/null; do
        umount -l "$CHROOT/$d"
    done
done

mount --bind /dev "$CHROOT/dev"
mount --bind /proc "$CHROOT/proc"
mount --bind /sys "$CHROOT/sys"
MISSING_LIBS="$(chroot "$CHROOT" ldd /opt/roohaniye/bin/roohaniye-shell 2>/dev/null | grep "not found" || true)"

# Installer wizard dependency check. parted/dosfstools/rsync/partprobe
# were verified already present in the chroot (2026-07-18) - only
# cryptsetup was actually missing, needed for LUKS-encrypted disk
# detection/handling in installerbackend.cpp. Installed idempotently
# here so every rebuild keeps it present without a full re-bootstrap.
if ! chroot "$CHROOT" dpkg -s cryptsetup >/dev/null 2>&1; then
    echo "   Installing missing package into chroot: cryptsetup"
    chroot "$CHROOT" /bin/bash -c "export DEBIAN_FRONTEND=noninteractive && apt-get update -qq && apt-get install -y --no-install-recommends cryptsetup"
else
    echo "   cryptsetup already present in chroot"
fi

# openssh-server: lets us SSH into a booted live/installed system for
# debugging when the GUI/touch input is unusable (e.g. tablets with no
# working touchscreen and no easy VT switch). Installed + enabled
# idempotently, same pattern as cryptsetup above. Login: roohaniye /
# roohaniye (see 0100-setup-roohaniye.hook.chroot for the account).
if ! chroot "$CHROOT" dpkg -s openssh-server >/dev/null 2>&1; then
    echo "   Installing missing package into chroot: openssh-server"
    chroot "$CHROOT" /bin/bash -c "export DEBIAN_FRONTEND=noninteractive && apt-get update -qq && apt-get install -y --no-install-recommends openssh-server"
else
    echo "   openssh-server already present in chroot"
fi
chroot "$CHROOT" systemctl enable ssh
# Ensure password auth is on - default Debian/Ubuntu sshd_config already
# allows it, but pin it explicitly so this can't silently break if the
# packaged default ever changes.
sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication yes/' "$CHROOT/etc/ssh/sshd_config"

# udisks2 (+ its polkit dependency): confirmed missing from the chroot on
# 2026-07-19 - the Debug Console backend shells out to `udisksctl` for
# both the internal-disk retry mount and the USB-drive fallback (see
# debugbackend.cpp findInternalDiskMountPoint/findOrMountUsbDrive), and
# without the package installed that binary silently doesn't exist, so
# both mount paths were failing to even start and only the ephemeral
# home-folder option ever showed up in the disk picker. Same idempotent
# install pattern as cryptsetup/openssh-server above.
if ! chroot "$CHROOT" dpkg -s udisks2 >/dev/null 2>&1; then
    echo "   Installing missing package into chroot: udisks2"
    chroot "$CHROOT" /bin/bash -c "export DEBIAN_FRONTEND=noninteractive && apt-get update -qq && apt-get install -y --no-install-recommends udisks2 policykit-1"
else
    echo "   udisks2 already present in chroot"
fi

# Auto-mounts deviceA's real internal NVMe drive at /mnt/internal-disk on
# boot (by UUID, so it's a no-op/harmless on different hardware like
# deviceB) - lets the Debug Console's log fallback chain reach a path
# that's still there after rebooting back into normal Ubuntu, since a
# live USB boot never touches the real internal disk otherwise. (Actual
# cp/systemctl enable for this unit happens further below, after the
# rfkill/touchscreen fixes.)

# rfkill + iw: confirmed missing from the chroot on 2026-07-19 - the
# Debug Console diagnostics showed mac80211/cfg80211/mt76 (MediaTek
# MT7921) wifi modules loaded fine, but `rfkill: command not found` and
# `lspci`/`lsusb` also missing, and nmcli reporting the wifi device as
# "unavailable" rather than "disconnected". Without rfkill installed we
# can't even inspect (let alone clear) a soft-block, and without iw we
# can't manually scan/debug the radio. Same idempotent install pattern
# as udisks2/openssh-server above.
if ! chroot "$CHROOT" dpkg -s rfkill >/dev/null 2>&1; then
    echo "   Installing missing package into chroot: rfkill, iw"
    chroot "$CHROOT" /bin/bash -c "export DEBIAN_FRONTEND=noninteractive && apt-get update -qq && apt-get install -y --no-install-recommends rfkill iw"
else
    echo "   rfkill/iw already present in chroot"
fi

# wpasupplicant: confirmed 2026-07-20 that it was listed in
# roohaniye.list.chroot but never actually installed into this
# persistent chroot (dpkg -l showed "un"). Without it, NetworkManager
# can't D-Bus-activate fi.w1.wpa_supplicant1 for wlp2s0, which is the
# real cause of nmcli reporting the device "unavailable" even though
# the driver/firmware/rfkill are all fine - confirmed directly via
# nm-wifi-diagnostic-fix.service's journal capture:
#   "Couldn't initialize supplicant interface: Failed to D-Bus
#   activate wpa_supplicant service"
# Same idempotent install pattern as rfkill/iw above.
if ! chroot "$CHROOT" dpkg -s wpasupplicant >/dev/null 2>&1; then
    echo "   Installing missing package into chroot: wpasupplicant"
    chroot "$CHROOT" /bin/bash -c "export DEBIAN_FRONTEND=noninteractive && apt-get update -qq && apt-get install -y --no-install-recommends wpasupplicant"
else
    echo "   wpasupplicant already present in chroot"
fi

# Belt-and-suspenders fix for the "wifi unavailable" symptom above: some
# laptops persist a software rfkill soft-block across boots (systemd-rfkill's
# saved state, or default-blocked until unblocked once) even though the
# driver/firmware are loaded correctly. Unblock everything right before the
# kiosk shell starts. Idempotent/harmless if nothing is actually blocked.
cp "$SCRIPT_DIR/config-src/rfkill-unblock.service" "$CHROOT/etc/systemd/system/rfkill-unblock.service"
chroot "$CHROOT" systemctl enable rfkill-unblock.service

# Touchscreen input: eglfs's libinput backend (see main.cpp forcing eglfs)
# needs the running user to actually have permission to read /dev/input/event*
# - normally granted via udev's uaccess ACL tagging for the active logind
# seat, but add the "input" group explicitly too as a belt-and-suspenders
# fix in case that ACL path doesn't apply cleanly for this service unit's
# PAMName=login + TTYPath=/dev/tty1 setup. Idempotent - safe to rerun.
#
# IMPORTANT: confirmed on 2026-07-19 that this chroot never actually had
# the base kiosk setup applied at all - no "roohaniye" user in
# /etc/passwd (only the stock casper "ubuntu" account at uid 1000), and
# no roohaniye-shell.service unit installed/enabled. Every "live boot"
# test done so far was actually the plain Ubuntu desktop session
# (autologin as "ubuntu", full GNOME), with the app run manually inside
# it - NOT the real tty1-autologin kiosk boot path this whole project is
# meant to produce. Fix that here, idempotently, matching exactly what
# config-src/0100-setup-roohaniye.hook.chroot does (that hook is only
# consulted by `lb build` from scratch, which this script deliberately
# doesn't do - see the top-of-file comment).
if ! chroot "$CHROOT" id roohaniye >/dev/null 2>&1; then
    echo "   roohaniye user missing - creating it now (this chroot never had the kiosk account set up)"
    # Guard against required groups not existing - confirmed on 2026-07-19
    # that "netdev" was missing even though network-manager is installed,
    # likely because some package postinst scripts fail silently in this
    # chroot (see the "Can not write log (Is /dev/pts mounted?)" apt
    # warnings above). Create any of these idempotently if absent rather
    # than trusting package postinst to have done it.
    for grp in video audio plugdev netdev input; do
        chroot "$CHROOT" getent group "$grp" >/dev/null 2>&1 || chroot "$CHROOT" groupadd "$grp"
    done
    chroot "$CHROOT" useradd -m -s /bin/bash -G video,audio,plugdev,netdev,input roohaniye
    chroot "$CHROOT" /bin/bash -c "echo 'roohaniye:roohaniye' | chpasswd"
else
    echo "   roohaniye user already present in chroot"
fi

# UID 1000 fix - confirmed 2026-07-23 that roohaniye-shell.service was
# running but taking NO input at all (Tasks: 0 in systemctl status, tiny
# ~3MB memory footprint - eglfs failing silently very early, not a
# crash) because roohaniye ended up on uid 1001, not 1000. Root cause:
# casper's own live-session default account ("ubuntu") is created by the
# live-build/casper framework itself (NOT this script or the hook
# script) and always claims uid 1000 first, so plain `useradd` above
# picks the next free uid (1001) every time. But
# roohaniye-shell.service hardcodes Environment=XDG_RUNTIME_DIR=/run/
# user/1000 (matching the `mkdir -p .../run/user/1000` a few lines
# below) - with the real user at 1001, that runtime dir doesn't exist
# for the process, silently breaking EGL/DRM/seat access in eglfs with
# no crash and no useful log output (see build.md Section G's dmesg/
# libinput diagnostic flow for how this was actually tracked down).
#
# Fix: the "ubuntu" account is never used by anything in this project
# (roohaniye-kiosk.service, the one thing that ran as it, is already
# disabled above as stale/superseded) - remove it to free uid 1000, then
# force roohaniye onto uid/gid 1000 explicitly. Idempotent and
# self-healing: also fixes a roohaniye account baked in at the wrong uid
# by an earlier flawed build, not just fresh ones.
if chroot "$CHROOT" id ubuntu >/dev/null 2>&1; then
    echo "   Removing unused stock 'ubuntu' account to free uid 1000"
    chroot "$CHROOT" userdel -r ubuntu 2>/dev/null || chroot "$CHROOT" userdel ubuntu
fi
ROOHANIYE_UID="$(chroot "$CHROOT" id -u roohaniye)"
if [ "$ROOHANIYE_UID" != "1000" ]; then
    echo "   Correcting roohaniye uid/gid $ROOHANIYE_UID -> 1000 (was wrong due to the casper-ubuntu-uid-1000 conflict above)"
    chroot "$CHROOT" usermod -u 1000 roohaniye
    chroot "$CHROOT" groupmod -g 1000 roohaniye
    # Fix ownership of anything the old uid/gid already touched (home dir,
    # /run/user/<old-uid> if it exists, etc.) before it's gone for good.
    chroot "$CHROOT" find / -xdev -user "$ROOHANIYE_UID" -exec chown -h roohaniye {} \; 2>/dev/null || true
    chroot "$CHROOT" find / -xdev -group "$ROOHANIYE_UID" -exec chgrp -h roohaniye {} \; 2>/dev/null || true
else
    echo "   roohaniye already at uid/gid 1000 - correct"
fi
mkdir -p "$CHROOT/run/user/1000"
chroot "$CHROOT" chown roohaniye:roohaniye /run/user/1000 2>/dev/null || true

# Passwordless sudo for roohaniye - confirmed 2026-07-19 that the in-app
# Debug Console's commands (rfkill, iw, dmesg, lspci, lsusb, etc.) need
# root, but QProcess has no TTY to let `sudo` prompt for a password, so
# every "sudo ..." entry in commands.txt was silently failing. See
# config-src/roohaniye-nopasswd for the full reasoning. Idempotent -
# always re-copy so an edit to the source file takes effect on rebuild
# without needing the "missing" check other idempotent steps use.
cp "$SCRIPT_DIR/config-src/roohaniye-nopasswd" "$CHROOT/etc/sudoers.d/roohaniye-nopasswd"
chmod 0440 "$CHROOT/etc/sudoers.d/roohaniye-nopasswd"
chroot "$CHROOT" visudo -cf /etc/sudoers.d/roohaniye-nopasswd

if [ ! -f "$CHROOT/etc/systemd/system/roohaniye-shell.service" ]; then
    echo "   roohaniye-shell.service unit missing - installing it now"
    cp "$SCRIPT_DIR/config-src/roohaniye-shell.service" "$CHROOT/etc/systemd/system/roohaniye-shell.service"
fi
chroot "$CHROOT" systemctl enable roohaniye-shell.service
chroot "$CHROOT" systemctl set-default graphical.target

# Stale unit from before the roohaniye account existed in this chroot
# (created 2026-07-18, back when the only account was the stock casper
# "ubuntu" user at uid 1000). Confirmed 2026-07-20 it's still enabled
# under multi-user.target.wants alongside roohaniye-shell.service -
# since multi-user.target is a dependency of graphical.target (the
# default target), BOTH would race for /dev/tty1 at boot. Worse,
# roohaniye-kiosk.service runs as User=ubuntu, which has none of the
# permission fixes applied since (passwordless sudo, netdev/video/
# plugdev/input groups, mount-internal-disk ownership) - all of that is
# wired to "roohaniye" specifically. Disabling idempotently; leaving the
# unit file itself in place for reference rather than deleting it.
if chroot "$CHROOT" systemctl is-enabled roohaniye-kiosk.service >/dev/null 2>&1; then
    echo "   Disabling stale roohaniye-kiosk.service (superseded by roohaniye-shell.service, wrong user)"
    chroot "$CHROOT" systemctl disable roohaniye-kiosk.service
else
    echo "   roohaniye-kiosk.service already disabled"
fi

chroot "$CHROOT" usermod -aG input roohaniye

cp "$SCRIPT_DIR/config-src/mount-internal-disk.service" "$CHROOT/etc/systemd/system/mount-internal-disk.service"
chroot "$CHROOT" systemctl enable mount-internal-disk.service

# Diagnoses (and works around) the common "rfkill says unblocked, driver
# loaded, iw scan finds APs, but nmcli still says unavailable" case -
# that's NetworkManager's OWN persisted software radio switch
# (NetworkManager.state's WIRELESS_ENABLED), a separate thing from kernel
# rfkill entirely. See config-src/nm-wifi-diagnostic-fix.service for the
# full explanation.
cp "$SCRIPT_DIR/config-src/nm-wifi-diagnostic-fix.service" "$CHROOT/etc/systemd/system/nm-wifi-diagnostic-fix.service"
chroot "$CHROOT" systemctl enable nm-wifi-diagnostic-fix.service

# casper-md5check.service (stock Ubuntu casper package, enabled by
# default upstream) fails on this hardware - confirmed 2026-07-23 it
# exits non-zero on every boot with no useful log output. Not required
# for normal operation (it's an optional "verify the ISO wasn't
# corrupted" integrity check, separate from the actual boot path); mask
# it so it stops showing as a failed unit. Idempotent - mask is a no-op
# if already masked.
chroot "$CHROOT" systemctl mask casper-md5check.service

# rsyslog / apport / accounts-daemon: THREE services now confirmed to
# hang boot indefinitely on real hardware (2026-07-23), one at a time
# across successive test boots, no timeout, no useful log output before
# the stall. None are needed for a kiosk appliance (no syslog consumer,
# no crash-dump storage set up, no desktop-session account UI - the app
# has its own AuthBackend). These masks previously existed ONLY in
# config-src/0100-setup-roohaniye.hook.chroot, which is NOT run by this
# script (see the file-header note) - they were silently never applied
# to any chroot build.sh actually produced. Fixed here now; if a FOURTH
# service shows the same symptom, stop masking individually and instead
# boot successfully once and run `systemd-analyze blame` to look for a
# shared systemic cause (e.g. degraded I/O on the writable overlay)
# rather than continuing to whack-a-mole each new one.
chroot "$CHROOT" systemctl mask rsyslog.service
chroot "$CHROOT" systemctl mask apport.service
chroot "$CHROOT" systemctl mask accounts-daemon.service

# Silead touchscreen firmware bundle (~70 files, github.com/onitake/
# gsl-firmware) - same gap as the masks above: this was only ever in
# the hook script, never mirrored here, so no chroot build.sh has
# actually produced yet had working touch, even after the live
# on-device fix (that fix only patched the running USB session, not
# this source chroot). See config-src/0100-setup-roohaniye.hook.chroot
# for the full explanation of why both filenames are installed.
mkdir -p "$CHROOT/lib/firmware/silead"
cp "$SCRIPT_DIR/config-src/silead-firmware/"*.fw "$CHROOT/lib/firmware/silead/"
cp "$CHROOT/lib/firmware/silead/gsl1680-globalspace-solt-ivw116.fw" \
   "$CHROOT/lib/firmware/silead/mssl1680.fw"

for d in dev proc sys; do
    while mountpoint -q "$CHROOT/$d" 2>/dev/null; do
        umount -l "$CHROOT/$d"
    done
done
if [ -n "$MISSING_LIBS" ]; then
    echo "WARNING: missing libraries in chroot - see build.md Section B to install them:" >&2
    echo "$MISSING_LIBS" >&2
fi

echo "== 3. Copying binary + databases into chroot =="
cp "$SHELL_BIN" "$CHROOT/opt/roohaniye/bin/roohaniye-shell"
chmod +x "$CHROOT/opt/roohaniye/bin/roohaniye-shell"

cp "$SCRIPT_DIR/config-src/debug-console.sh" "$CHROOT/usr/local/bin/debug-console"
chmod +x "$CHROOT/usr/local/bin/debug-console"

mkdir -p "$CHROOT/etc/systemd/system/getty@tty2.service.d"
cp "$SCRIPT_DIR/config-src/getty-tty2-debug-console.conf" "$CHROOT/etc/systemd/system/getty@tty2.service.d/override.conf"

# Auto-launch debug-console from roohaniye's own shell startup on tty2 -
# see roohaniye-bash-profile for why this replaced the old
# ExecStartPost approach (no controlling terminal there, so any sudo
# prompt inside the script had nowhere to actually appear).
cp "$SCRIPT_DIR/config-src/roohaniye-bash-profile" "$CHROOT/home/roohaniye/.bash_profile"
chroot "$CHROOT" chown roohaniye:roohaniye /home/roohaniye/.bash_profile

# Built-in fallback command list for the in-app Debug Console tile - the
# app checks a USB stick's root for commands.txt first (editable without
# rebuilding), falling back to this copy. See debugbackend.cpp.
cp "$SCRIPT_DIR/config-src/commands.txt" "$CHROOT/opt/roohaniye/data/commands.txt"

cp "$QURAN_TEXT_DB" "$CHROOT/opt/roohaniye/data/quran_text.db"
cp "$HADITHS_DB" "$CHROOT/opt/roohaniye/data/hadiths.db"

if [ "$INCLUDE_AUDIO" -eq 1 ]; then
    echo "   (staging quran_audio.db - ~21GB, this will take a while)"
    cp "$QURAN_AUDIO_DB" "$CHROOT/opt/roohaniye/data/quran_audio.db"
else
    echo "   (quran_audio.db NOT included - import later via Database Connector)"
    rm -f "$CHROOT/opt/roohaniye/data/quran_audio.db"
fi

if [ "$INCLUDE_MUSHAF" -eq 1 ]; then
    echo "   (staging mushafs.db - ~5.4GB, this will take a while)"
    cp "$MUSHAFS_DB" "$CHROOT/opt/roohaniye/data/mushafs.db"
else
    echo "   (mushafs.db NOT included - Mushaf reader won't have page scans on this build)"
    rm -f "$CHROOT/opt/roohaniye/data/mushafs.db"
fi

echo "== 4. Rebuilding squashfs + manifest + size =="
rm -f "$CHROOT/binary/casper/filesystem.squashfs"
mksquashfs "$CHROOT" "$CHROOT/binary/casper/filesystem.squashfs" \
    -e boot -noappend -comp xz

chroot "$CHROOT" dpkg-query -W --showformat='${Package} ${Version}\n' \
    > "$CHROOT/binary/casper/filesystem.manifest"

printf '%s' "$(du -sx --block-size=1 "$CHROOT" | cut -f1)" \
    > "$CHROOT/binary/casper/filesystem.size"

echo "== 5. Rebuilding the ISO =="
# Plain ISO9660 caps any single file at 4GiB-1 (2^32-1 bytes) unless
# -iso-level 3 is set, which allows multi-extent files (xorriso splits
# one big file across up to 100 extents by default - plenty for a
# ~27GB squashfs). filesystem.squashfs blows past 4GB the moment
# quran_audio.db or mushafs.db is included, so xorriso aborts with
# "File exceeds size limit" unless this is set. grub-mkrescue has no
# flag for this and doesn't reliably forward extra args to the xorriso
# call it builds internally, so the fix is a tiny wrapper script (via
# --xorriso=) that inserts "-iso-level 3" right after the "-as mkisofs"
# grub-mkrescue always invokes with. Harmless to always use, even for
# the small base build.
XORRISO_WRAPPER="$SCRIPT_DIR/config-src/xorriso-large-iso.sh"
mkdir -p "$SCRIPT_DIR/config-src"
cat > "$XORRISO_WRAPPER" <<'WRAPPER_EOF'
#!/bin/bash
args=("$@")
new_args=()
n=${#args[@]}
i=0
while [ $i -lt $n ]; do
    new_args+=("${args[$i]}")
    if [ "${args[$i]}" = "-as" ] && [ "$((i+1))" -lt "$n" ] && [ "${args[$((i+1))]}" = "mkisofs" ]; then
        new_args+=("mkisofs" "-iso-level" "3")
        i=$((i+1))
    fi
    i=$((i+1))
done
exec /usr/bin/xorriso "${new_args[@]}"
WRAPPER_EOF
chmod +x "$XORRISO_WRAPPER"

EXISTING_MAX=0
for f in "$SCRIPT_DIR"/RoohaniyeNoorIlm-vgrub*.iso; do
    [ -e "$f" ] || continue
    n="$(echo "$f" | sed -E 's/.*vgrub([0-9]+).*/\1/')"
    if [ "$n" -gt "$EXISTING_MAX" ] 2>/dev/null; then
        EXISTING_MAX="$n"
    fi
done
NEXT=$((EXISTING_MAX + 1))
FINAL="$SCRIPT_DIR/RoohaniyeNoorIlm-vgrub${NEXT}-${VARIANT}.iso"

grub-mkrescue --xorriso="$XORRISO_WRAPPER" -volid ROOHANIYE -o "$FINAL" "$CHROOT/binary/"
chown "$REAL_USER":"$REAL_USER" "$FINAL"

echo "== DONE ($VARIANT): $FINAL =="
ls -lh "$FINAL"
echo
echo "Test it with (see build.md Section A step 6 for the full OVMF invocation):"
echo "  qemu-system-x86_64 -m 2048 -drive file=\"$FINAL\",format=raw,media=cdrom -boot menu=on -display gtk"

# Auto-cleanup: each build.sh run adds a new ISO and nothing ever removed
# old ones - confirmed 2026-07-20 this had silently grown to 76GB across
# 31 accumulated "-base" ISOs alone before a manual cleanup. Keep the
# newest KEEP_N per variant (by mtime, which always matches build/version
# order here) and remove anything older, per-variant so this never eats
# a variant you're actively relying on just because another variant got
# rebuilt more often.
KEEP_N=3
for v in base audio mushaf full; do
    mapfile -t old_isos < <(ls -t "$SCRIPT_DIR"/RoohaniyeNoorIlm-vgrub*-"$v".iso 2>/dev/null | tail -n +$((KEEP_N + 1)))
    for old in "${old_isos[@]}"; do
        echo "   Cleanup: removing superseded build artifact $(basename "$old")"
        rm -f "$old"
    done
done
