#!/bin/bash
# RoohaniyeNoorIlm Debug Console
#
# Purpose: a simple always-available diagnostics shell for when the
# touchscreen/GUI/WiFi isn't working. Everything you type AND everything
# printed back is logged to a file on a separate writable USB stick (not
# the live-boot media itself, which is read-only, and not the internal
# disk), so it can be read on another machine afterwards.
#
# How to reach it on a booted ISO with no working touchscreen/network:
#   Ctrl+Alt+F2  -> switch to a text VT, log in as roohaniye/roohaniye,
#   then run:  sudo debug-console
# (build.sh also wires this up to auto-launch on tty2, see below.)

set -u

LOGDIR_NAME="roohaniye-debug-logs"
MOUNT_BASE="/mnt/roohaniye-debug"
INTERNAL_DISK_MOUNT="/mnt/internal-disk"

echo "== RoohaniyeNoorIlm Debug Console =="

# Figure out which device the live system itself booted from, so we
# never offer it as a log target (it's the read-only squashfs/ISO media).
BOOT_SRC="$(findmnt -n -o SOURCE / 2>/dev/null || true)"
BOOT_DISK=""
if [ -n "$BOOT_SRC" ]; then
    BOOT_DISK="$(lsblk -no PKNAME "$BOOT_SRC" 2>/dev/null || true)"
fi

# --- Step 1: build a numbered list of disks/mountpoints to choose from ---
#
# CHOICE_MOUNT[i]  -> absolute path logs could be written under for
#                      choice i (already mounted by the time it's listed)
# CHOICE_LABEL[i]  -> human-readable description shown in the menu
declare -a CHOICE_MOUNT=()
declare -a CHOICE_LABEL=()

echo "Scanning for writable disks..."

while IFS= read -r line; do
    name="$(echo "$line" | awk '{print $1}')"
    fstype="$(echo "$line" | awk '{print $2}')"
    size="$(echo "$line" | awk '{print $3}')"
    rm_flag="$(echo "$line" | awk '{print $4}')"
    existing_mp="$(echo "$line" | awk '{print $5}')"
    [ -n "$fstype" ] || continue
    disk="$(lsblk -no PKNAME "/dev/$name" 2>/dev/null || true)"
    [ "$disk" = "$BOOT_DISK" ] && continue

    if [ -n "$existing_mp" ] && [ "$existing_mp" != "-" ]; then
        # Already mounted somewhere (e.g. an internal partition) - just
        # use that mountpoint as-is, don't remount it.
        mp="$existing_mp"
    else
        mp="$MOUNT_BASE/$name"
        sudo mkdir -p "$mp"
        if ! mountpoint -q "$mp"; then
            sudo mount "/dev/$name" "$mp" 2>/dev/null
        fi
        mountpoint -q "$mp" || continue
    fi

    kind="internal"
    [ "$rm_flag" = "1" ] && kind="removable/USB"
    CHOICE_MOUNT+=("$mp")
    CHOICE_LABEL+=("/dev/$name  [$fstype, $size, $kind]  -> $mp")
done < <(lsblk -rno NAME,FSTYPE,SIZE,RM,MOUNTPOINT)

# The internal disk mount unit (mount-internal-disk.service) may have
# already mounted deviceA's real disk here at boot - but since you're
# on tty2 specifically because the GUI failed, you're often here before
# that boot-time unit has actually finished (there's no explicit
# ordering between it and getty@tty2, so it's a race). Don't just trust
# it happened - actively retry the same mount right now if it hasn't.
INTERNAL_DISK_UUID="53001e86-aaab-4485-a7f9-61865a52f2c9"
if ! mountpoint -q "$INTERNAL_DISK_MOUNT" 2>/dev/null; then
    sudo mkdir -p "$INTERNAL_DISK_MOUNT"
    sudo mount -U "$INTERNAL_DISK_UUID" "$INTERNAL_DISK_MOUNT" 2>/dev/null
fi
if mountpoint -q "$INTERNAL_DISK_MOUNT" 2>/dev/null; then
    already_listed=0
    for m in "${CHOICE_MOUNT[@]:-}"; do
        [ "$m" = "$INTERNAL_DISK_MOUNT" ] && already_listed=1
    done
    if [ "$already_listed" -eq 0 ]; then
        CHOICE_MOUNT+=("$INTERNAL_DISK_MOUNT")
        CHOICE_LABEL+=("deviceA's internal disk  -> $INTERNAL_DISK_MOUNT")
    fi
fi

echo
if [ "${#CHOICE_MOUNT[@]}" -eq 0 ]; then
    echo "No writable disks found (no USB stick plugged in, no internal"
    echo "disk mounted). Plug one in and run 'debug-console' again."
    echo "Continuing anyway - logs will only be saved to /tmp."
    CHOSEN_BASE="/tmp"
else
    i=1
    for label in "${CHOICE_LABEL[@]}"; do
        echo "  [$i] $label"
        i=$((i + 1))
    done
    echo "  [t] /tmp only (log will NOT survive reboot)"
    echo
    printf "Pick a disk to log to (number, or 't'): "
    read -r disk_choice
    if [ "$disk_choice" = "t" ] || [ "$disk_choice" = "T" ]; then
        CHOSEN_BASE="/tmp"
    elif echo "$disk_choice" | grep -qE '^[0-9]+$' \
        && [ "$disk_choice" -ge 1 ] \
        && [ "$disk_choice" -le "${#CHOICE_MOUNT[@]}" ]; then
        CHOSEN_BASE="${CHOICE_MOUNT[$((disk_choice - 1))]}"
    else
        echo "Not a valid choice - defaulting to /tmp."
        CHOSEN_BASE="/tmp"
    fi
fi

# --- Step 2: browse into a folder on the chosen disk ---
#
# Lets the user navigate down into subfolders (or create a new one)
# before we start logging there. Skipped entirely for /tmp.
browse_folder() {
    # IMPORTANT: this function's return value is its final "$dir" on
    # stdout, captured by the caller via $(...). Every other line of
    # menu/prompt output must go to the terminal directly (>&2), or it
    # would get swallowed into the captured path instead of being shown.
    local dir="$1"
    while true; do
        echo >&2
        echo "Current folder: $dir" >&2
        local -a subdirs=()
        while IFS= read -r d; do
            [ -n "$d" ] && subdirs+=("$d")
        done < <(find "$dir" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort)

        if [ "${#subdirs[@]}" -eq 0 ]; then
            echo "  (no subfolders here)" >&2
        else
            local i=1
            for d in "${subdirs[@]}"; do
                echo "  [$i] $d/" >&2
                i=$((i + 1))
            done
        fi
        echo "  [s] Save logs HERE, in this folder" >&2
        echo "  [n] Create a new folder here" >&2
        if [ "$dir" != "$CHOSEN_BASE" ]; then
            echo "  [u] Up one level" >&2
        fi
        printf "Choice: " >&2
        read -r choice

        case "$choice" in
            s|S)
                echo "$dir"
                return 0
                ;;
            n|N)
                printf "New folder name: " >&2
                read -r newname
                if [ -n "$newname" ] && sudo mkdir -p "$dir/$newname" 2>/dev/null; then
                    sudo chmod 777 "$dir/$newname" 2>/dev/null
                    dir="$dir/$newname"
                else
                    echo "Could not create that folder - try again." >&2
                fi
                ;;
            u|U)
                if [ "$dir" != "$CHOSEN_BASE" ]; then
                    dir="$(dirname "$dir")"
                fi
                ;;
            *)
                if echo "$choice" | grep -qE '^[0-9]+$' \
                    && [ "$choice" -ge 1 ] \
                    && [ "$choice" -le "${#subdirs[@]}" ]; then
                    dir="$dir/${subdirs[$((choice - 1))]}"
                else
                    echo "Not a valid choice." >&2
                fi
                ;;
        esac
    done
}

if [ "$CHOSEN_BASE" = "/tmp" ]; then
    TARGET_DIR="/tmp"
else
    TARGET_DIR="$(browse_folder "$CHOSEN_BASE")"
fi

sudo mkdir -p "$TARGET_DIR/$LOGDIR_NAME" 2>/dev/null
sudo chmod 777 "$TARGET_DIR/$LOGDIR_NAME" 2>/dev/null
if [ -d "$TARGET_DIR/$LOGDIR_NAME" ] && [ -w "$TARGET_DIR/$LOGDIR_NAME" ]; then
    LOGFILE="$TARGET_DIR/$LOGDIR_NAME/session-$(date +%Y%m%d-%H%M%S).txt"
else
    echo "Could not write to $TARGET_DIR - falling back to /tmp."
    LOGFILE="/tmp/roohaniye-debug-session-$(date +%Y%m%d-%H%M%S).txt"
fi
echo
echo "Logging this session to: $LOGFILE"

{
    echo "=== RoohaniyeNoorIlm debug session started $(date) ==="
    echo "--- uname -a ---"
    uname -a
    echo "--- lsmod (wifi/bt related) ---"
    lsmod | grep -iE "80211|rtl|brcm|ath|iwl|mwifiex|bluetooth" || echo "(none loaded)"
    echo "--- nmcli device status ---"
    nmcli device status 2>&1 || echo "(nmcli unavailable)"
    echo "--- lsblk -f ---"
    lsblk -f
    echo "--- dmesg tail (last 60 lines) ---"
    dmesg 2>/dev/null | tail -60 || echo "(dmesg needs root - re-run with sudo)"
    echo "--- rfkill list ---"
    sudo rfkill list 2>&1
    echo "--- wifi/mt76/firmware kernel log (needs root; password prompt is normal here - roohaniye/roohaniye) ---"
    sudo dmesg 2>&1 | grep -iE "mt76|mt7921|firmware|wifi|regdom" || echo "(no matching lines, or sudo needs the roohaniye password)"
    echo "======================================================="
    echo "Dropping into an interactive shell now."
    echo "Everything you type and everything printed will be saved."
    echo "Type 'exit' when done."
    echo "======================================================="
} | tee -a "$LOGFILE"

# `script` records the full interactive session (input + output) to
# LOGFILE, appending to the header we just wrote above.
script -a -q -c "/bin/bash --login" "$LOGFILE"

echo
echo "Session ended. Full log saved to: $LOGFILE"
