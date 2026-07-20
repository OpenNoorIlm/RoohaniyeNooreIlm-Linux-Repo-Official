// DebugBackend: an in-app diagnostics console, exposed as a Home Screen
// tile like every other app here (Quran, Hadith, Prayer Times, ...)
// rather than a hidden keyboard shortcut - so it's reachable by anyone
// using this device, even with a mouse/touch only setup.
//
// Runs arbitrary shell commands via QProcess (same "shell out to simple
// mechanisms" philosophy as WifiBackend/PowerBackend/StorageBackend in
// this project) and appends every command + its output to a timestamped
// log file. The log always goes to a REMOVABLE USB/SD device (reusing
// StorageBackend's existing detection - see storagebackend.h) rather
// than the internal disk, so it can be read on another machine
// afterwards even if this device's WiFi/network is what's broken.
#pragma once

#include <QObject>
#include <QString>
#include <QVariantList>

class StorageBackend;

class DebugBackend : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString logFilePath READ logFilePath NOTIFY logFilePathChanged)

public:
    // Takes a raw StorageBackend* (not owned) purely to read its
    // already-detected removable-device list - same pattern DbConnectorBackend
    // uses for QuranBackend*.
    explicit DebugBackend(StorageBackend *storageBackend, QObject *parent = nullptr);

    QString logFilePath() const { return m_logFilePath; }

    // Runs `cmd` via /bin/bash -c, waits up to 15s, returns combined
    // stdout+stderr as one string. Also appends the command + output to
    // the session log file (created lazily on first call).
    Q_INVOKABLE QString runCommand(const QString &cmd);

    // Runs a fixed set of common WiFi/hardware diagnostic commands in
    // one go (uname, lsmod, nmcli, lsblk, dmesg tail, lspci) - the same
    // set a person would otherwise have to type one at a time.
    Q_INVOKABLE QString runDiagnostics();

    // Loads the command list from commands.txt - checks the root of any
    // inserted USB/SD device first (so it can be edited without
    // rebuilding the ISO), falling back to the built-in copy shipped at
    // /opt/roohaniye/data/commands.txt. Each entry: {label, cmd}.
    Q_INVOKABLE QVariantList loadCommandList();

    // Path actually used by the last loadCommandList() call, for
    // display purposes (so the user can see whether their USB override
    // was picked up or the built-in list was used instead).
    Q_INVOKABLE QString commandListSource() const { return m_commandListSource; }

    // Runs every command currently in commands.txt (USB override or
    // built-in, whichever loadCommandList() would pick), in order,
    // logging each one. Returns a list of {label, cmd, output} so the
    // QML view can push them all into the visible history in one go.
    Q_INVOKABLE QVariantList runAllFromFile();

    // Whether a removable USB/SD device is currently available to log to
    // (mirrors storageBackend.storagePresent, exposed here too so the
    // QML view doesn't need to reach into storageBackend directly).
    Q_INVOKABLE bool hasLogTarget() const;

    // Lists every place logs could be saved: every currently-detected
    // removable USB/SD device, the internal disk if mounted at
    // /mnt/internal-disk (kiosk/live-boot case), and this device's home
    // folder as an always-available option (normal desktop dev case).
    // Each entry: {label, path, removable}.
    Q_INVOKABLE QVariantList listLogTargetDisks() const;

    // Lists immediate subfolders of `path`. Each entry: {name, path}.
    Q_INVOKABLE QVariantList listFolders(const QString &path) const;

    // Same as listFolders(), but distinguishes "genuinely empty" from
    // "couldn't be read" (permission denied) - QDir::entryInfoList()
    // returns an empty list in BOTH cases, which looks identical to the
    // user (e.g. browsing into another Linux user's mode-750 home dir as
    // roohaniye: silently shows nothing, indistinguishable from "no
    // subfolders here"). Returns {"ok": true/false, "reason": "..."}
    // alongside the same folder list listFolders() would give.
    Q_INVOKABLE QVariantMap checkFolderAccess(const QString &path) const;

    // Creates `name` as a subfolder of `parentPath`. Returns the new
    // folder's full path on success, or an empty string on failure.
    Q_INVOKABLE QString createFolder(const QString &parentPath, const QString &name);

    // Explicitly sets where logs go, chosen via the disk+folder picker.
    // Starts a fresh log file under `dir` the next time a command runs.
    // NOTE: does NOT verify writability - kept only for backward
    // compatibility. Prefer trySelectLogDirectory() below, which actually
    // tests the folder before committing to it, so a bad pick (e.g. another
    // user's home folder) is rejected immediately with a clear reason
    // instead of silently being overridden later by ensureLogFile()'s
    // auto-detect fallback with zero indication to the user.
    Q_INVOKABLE void selectLogDirectory(const QString &dir);

    // Same intent as selectLogDirectory(), but actually tests write access
    // to `dir` first (same real write-probe ensureLogFile() itself uses,
    // not just a permission-bit guess). Only commits the selection if the
    // probe succeeds. Returns {"ok": true} on success, or {"ok": false,
    // "reason": "..."} on failure (with the same owner/permissions detail
    // checkFolderAccess() gives) - the selection is left unchanged in the
    // failure case, so QML can show the error and let the user pick again
    // instead of silently falling through to wherever ensureLogFile()'s
    // auto-detect chain lands.
    Q_INVOKABLE QVariantMap trySelectLogDirectory(const QString &dir);

    Q_INVOKABLE QString selectedLogDir() const { return m_selectedLogDir; }

signals:
    void logFilePathChanged();

private:
    void ensureLogFile();
    void appendToLog(const QString &text);

    // Resolves where the internal disk is actually reachable, retrying the
    // mount ourselves (via udisksctl, unprivileged) if mount-internal-disk.service
    // didn't get there first or failed at boot. Returns the real mountpoint
    // path, or an empty string if the disk/UUID isn't present on this hardware
    // at all. See debugbackend.cpp for why /mnt/internal-disk alone can't be
    // trusted as "mounted" just because the directory exists.
    QString findInternalDiskMountPoint() const;

    // Runs `udisksctl mount -b <devicePath>` and parses out the real
    // mountpoint it lands at (or finds it via QStorageInfo::mountedVolumes()
    // if parsing the message fails, e.g. because it was already mounted a
    // moment earlier by something else). Shared by the internal-disk and
    // USB-drive lookups below. Returns empty string on failure.
    QString runUdisksctlMount(const QString &devicePath) const;

    // Finds a removable (USB/SD) disk by walking /sys/block directly - does
    // NOT depend on a desktop auto-mount daemon (gvfs/udisksd via a full
    // session) having already mounted it under /media/$USER, since this
    // kiosk shell doesn't run one. Mounts the first unmounted partition
    // found via udisksctl if needed. Returns the real mountpoint, or empty
    // if no removable disk is present at all.
    QString findOrMountUsbDrive() const;

    StorageBackend *m_storageBackend;
    QString m_logFilePath; // empty until first successful command, or no storage found
    QString m_commandListSource; // path of commands.txt actually used, for display
    QString m_selectedLogDir; // explicit dir chosen via the disk+folder picker; empty = old auto-detect behavior
};
