#include "debugbackend.h"
#include "storagebackend.h"

#include <QProcess>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QTextStream>
#include <QStandardPaths>
#include <QStorageInfo>
#include <QRegularExpression>

// Must match live-build/config-src/mount-internal-disk.service and
// debug-console.sh exactly - this is deviceA's real internal disk, used as
// the debug-log fallback target on a fresh live-boot ISO.
static const char *INTERNAL_DISK_UUID = "53001e86-aaab-4485-a7f9-61865a52f2c9";

// Fixed fallback location for debugging on deviceA directly (running the
// compiled binary on the normal desktop session rather than a fresh ISO
// boot) - used only when no removable USB/SD is detected. Deliberately
// named so it's obvious this is scratch debug output, not user data.
// NOTE: only actually reachable when this binary is run as the same user
// that owns ~/Downloads (i.e. running it directly on deviceA's normal
// desktop session for local testing). On a live-boot kiosk session this
// runs as the unprivileged "roohaniye" account, a different uid than
// whoever owns /home/bismillah - roohaniye has no write access there at
// all, so this candidate will correctly fail and get skipped by the
// writability check in ensureLogFile() below rather than silently
// swallowing the log with no file ever actually written.
static const char *FALLBACK_LOG_DIR = "/home/bismillah/Downloads/logsDoNotTouch";

// Last-resort candidate that works for ANY user on ANY device - /tmp is
// always world-writable (sticky bit). Ephemeral (lost on reboot, and on
// a live session lost the moment the session ends), but "log written
// somewhere, even if temporary" beats silently writing nothing at all.
static const char *LAST_RESORT_LOG_DIR = "/tmp/roohaniye-debug-logs";

// Tests whether we can actually create+write a file under dir, not just
// whether the path string is non-empty. This is the check ensureLogFile()
// was missing entirely before - it used to trust the first non-empty
// candidate from the detection chain and never verified the write itself
// would succeed, so a permission-denied directory (e.g. a uid mismatch
// like roohaniye vs bismillah) produced a log path that silently never
// got a real file written to it, with no error surfaced anywhere.
static bool dirIsActuallyWritable(const QString &dir)
{
    if (dir.isEmpty())
        return false;
    if (!QDir().mkpath(dir))
        return false;
    const QString probePath = dir + "/.roohaniye-write-test";
    QFile probe(probePath);
    if (!probe.open(QIODevice::WriteOnly))
        return false;
    probe.close();
    probe.remove();
    return true;
}

DebugBackend::DebugBackend(StorageBackend *storageBackend, QObject *parent)
    : QObject(parent)
    , m_storageBackend(storageBackend)
{
}

bool DebugBackend::hasLogTarget() const
{
    return m_storageBackend && m_storageBackend->storagePresent();
}

void DebugBackend::ensureLogFile()
{
    if (!m_logFilePath.isEmpty())
        return; // already created this session

    QString logDir;
    if (!m_selectedLogDir.isEmpty()) {
        // User explicitly picked a disk+folder via the picker - always
        // honor that over auto-detection, but still verify it's actually
        // writable (they may have picked a folder before it later became
        // unwritable, e.g. a USB stick swapped out).
        if (dirIsActuallyWritable(m_selectedLogDir))
            logDir = m_selectedLogDir;
    }

    if (logDir.isEmpty()) {
        // Auto-detect, without requiring the user to have opened the disk
        // picker first - this is the path any command run "cold" (e.g.
        // tapping Run Diagnostics immediately) actually takes, so it needs
        // to try the real persistent-storage options itself rather than
        // only trusting StorageBackend's (gvfs/udisksd-dependent) device
        // list, which may be empty in this kiosk session even with a USB
        // stick plugged in and even with the internal disk reachable.
        //
        // Every candidate below is verified with dirIsActuallyWritable()
        // before being accepted - a candidate existing/being detected is
        // not the same as roohaniye actually having write permission on
        // it (e.g. the internal disk mount is deviceA's real filesystem,
        // top-level owned root:root - reachable but not writable unless
        // mount-internal-disk.service pre-created a writable subfolder).
        // Falling through on a failed write, instead of committing to the
        // first non-empty path, is what actually fixes the old silent
        // failure: previously a permission-denied candidate produced a
        // log path that quietly never got a real file written to it.

        // 1. Any detected removable USB/SD device (old path, kept for the
        // case where a full desktop automount daemon IS present).
        if (logDir.isEmpty() && hasLogTarget()) {
            const QVariantList devices = m_storageBackend->devices();
            const QString basePath = devices.isEmpty() ? QString() : devices.first().toMap().value("path").toString();
            if (!basePath.isEmpty()) {
                const QString candidate = basePath + "/roohaniye-debug-logs";
                if (dirIsActuallyWritable(candidate))
                    logDir = candidate;
            }
        }

        // 2. Find/mount a USB drive ourselves via udisksctl if the above
        // found nothing.
        if (logDir.isEmpty()) {
            const QString usbMount = findOrMountUsbDrive();
            if (!usbMount.isEmpty()) {
                const QString candidate = usbMount + "/roohaniye-debug-logs";
                if (dirIsActuallyWritable(candidate))
                    logDir = candidate;
            }
        }

        // 3. The internal disk, mounted (or retried via udisksctl) at
        // whatever real path it lands on - covers the live-boot/kiosk
        // case where mount-internal-disk.service raced or failed but the
        // disk is genuinely reachable another way.
        if (logDir.isEmpty()) {
            const QString internalMount = findInternalDiskMountPoint();
            if (!internalMount.isEmpty()) {
                const QString candidate = internalMount + "/roohaniye-debug-logs";
                if (dirIsActuallyWritable(candidate))
                    logDir = candidate;
            }
        }

        // 4. Fixed dev-machine fallback - only actually writable when
        // this binary runs as whoever owns that path (see comment above
        // FALLBACK_LOG_DIR); verified rather than assumed.
        if (logDir.isEmpty() && dirIsActuallyWritable(FALLBACK_LOG_DIR)) {
            logDir = FALLBACK_LOG_DIR;
        }

        // 5. True last resort - /tmp is always writable by anyone, on
        // any device, regardless of uid. Ephemeral, but guarantees the
        // log actually gets written somewhere instead of silently
        // vanishing.
        if (logDir.isEmpty()) {
            logDir = LAST_RESORT_LOG_DIR;
            QDir().mkpath(logDir);
        }
    }

    const QString stamp = QDateTime::currentDateTime().toString("yyyyMMdd-HHmmss");
    m_logFilePath = logDir + "/session-" + stamp + ".txt";

    QFile f(m_logFilePath);
    if (f.open(QIODevice::WriteOnly | QIODevice::Append | QIODevice::Text)) {
        QTextStream out(&f);
        out << "=== RoohaniyeNoorIlm Debug Console session started "
            << QDateTime::currentDateTime().toString(Qt::ISODate) << " ===\n";
        f.close();
    }

    emit logFilePathChanged();
}

void DebugBackend::appendToLog(const QString &text)
{
    ensureLogFile();
    if (m_logFilePath.isEmpty())
        return; // shouldn't happen now (ensureLogFile always picks a path), defensive only

    QFile f(m_logFilePath);
    if (f.open(QIODevice::WriteOnly | QIODevice::Append | QIODevice::Text)) {
        QTextStream out(&f);
        out << text;
        f.close();
    }
}

QString DebugBackend::runCommand(const QString &cmd)
{
    if (cmd.trimmed().isEmpty())
        return QString();

    QProcess proc;
    proc.setProcessChannelMode(QProcess::MergedChannels);
    proc.start("/bin/bash", QStringList() << "-c" << cmd);

    QString output;
    if (!proc.waitForStarted(3000)) {
        output = "[failed to start command]";
    } else if (!proc.waitForFinished(15000)) {
        proc.kill();
        proc.waitForFinished(2000);
        output = QString::fromUtf8(proc.readAll()) + "\n[command timed out after 15s and was killed]";
    } else {
        output = QString::fromUtf8(proc.readAll());
    }

    const QString stamp = QDateTime::currentDateTime().toString("HH:mm:ss");
    QString entry;
    entry += "\n[" + stamp + "] $ " + cmd + "\n";
    entry += output;
    if (!output.endsWith('\n'))
        entry += "\n";
    appendToLog(entry);

    return output;
}

QString DebugBackend::runDiagnostics()
{
    static const QString diagCmd =
        "echo '--- uname -a ---'; uname -a; "
        "echo '--- lsmod (wifi/bt) ---'; lsmod | grep -iE '80211|rtl|brcm|ath|iwl|mwifiex|bluetooth' || echo '(none loaded)'; "
        "echo '--- nmcli device status ---'; nmcli device status 2>&1; "
        "echo '--- rfkill ---'; rfkill list 2>&1 || echo '(rfkill not available)'; "
        "echo '--- lsblk -f ---'; lsblk -f 2>&1; "
        "echo '--- lspci -k (network controllers) ---'; lspci -k 2>&1 | grep -iA3 network || echo '(lspci not available)'; "
        "echo '--- dmesg tail ---'; dmesg 2>&1 | tail -40";

    return runCommand(diagCmd);
}

QVariantList DebugBackend::loadCommandList()
{
    QVariantList result;
    m_commandListSource.clear();

    // 1. Check the root of any inserted USB/SD device first, so the
    // list can be edited without rebuilding the ISO.
    QString path;
    if (m_storageBackend && m_storageBackend->storagePresent()) {
        const QVariantList devices = m_storageBackend->devices();
        for (const QVariant &dev : devices) {
            const QString candidate = dev.toMap().value("path").toString() + "/commands.txt";
            if (QFile::exists(candidate)) {
                path = candidate;
                break;
            }
        }
    }

    // 2. Fall back to the built-in copy shipped with the OS.
    if (path.isEmpty()) {
        const QString builtIn = "/opt/roohaniye/data/commands.txt";
        if (QFile::exists(builtIn))
            path = builtIn;
    }

    if (path.isEmpty())
        return result; // no file found anywhere - QML shows an empty state

    QFile f(path);
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text))
        return result;

    m_commandListSource = path;

    QTextStream in(&f);
    while (!in.atEnd()) {
        QString line = in.readLine().trimmed();
        if (line.isEmpty() || line.startsWith('#'))
            continue;

        QString label = line;
        QString cmd = line;
        const int sep = line.indexOf('|');
        if (sep >= 0) {
            label = line.left(sep).trimmed();
            cmd = line.mid(sep + 1).trimmed();
        }
        if (cmd.isEmpty())
            continue;

        QVariantMap entry;
        entry["label"] = label;
        entry["cmd"] = cmd;
        result.append(entry);
    }

    return result;
}

QVariantList DebugBackend::runAllFromFile()
{
    QVariantList results;
    const QVariantList list = loadCommandList();

    for (const QVariant &item : list) {
        const QVariantMap m = item.toMap();
        const QString label = m.value("label").toString();
        const QString cmd = m.value("cmd").toString();
        const QString output = runCommand(cmd);

        QVariantMap entry;
        entry["label"] = label;
        entry["cmd"] = cmd;
        entry["output"] = output;
        results.append(entry);
    }

    return results;
}

QString DebugBackend::findInternalDiskMountPoint() const
{
    // 1. Already mounted at the fixed path - the normal case when
    // mount-internal-disk.service ran successfully at boot.
    const QString fixedMount = "/mnt/internal-disk";
    const QStorageInfo fixedInfo(fixedMount);
    if (fixedInfo.isValid() && fixedInfo.rootPath() == fixedMount)
        return fixedMount;

    // 2. Not mounted yet - either the systemd unit failed/raced, or we're
    // running outside the normal boot sequence entirely. Retry the mount
    // ourselves via udisksctl - the same unprivileged mechanism a desktop
    // file manager uses to auto-mount a plugged-in USB stick, backed by
    // udisks2's default polkit rules for an active local session. No root
    // or pkexec prompt needed.
    const QString devicePath = QString("/dev/disk/by-uuid/%1").arg(INTERNAL_DISK_UUID);
    if (!QFileInfo::exists(devicePath))
        return QString(); // this UUID just isn't present on this hardware

    return runUdisksctlMount(devicePath);
}

QString DebugBackend::runUdisksctlMount(const QString &devicePath) const
{
    QProcess proc;
    proc.start("udisksctl", QStringList() << "mount" << "-b" << devicePath);
    if (!proc.waitForFinished(8000))
        return QString();

    const QString combined = QString::fromUtf8(proc.readAllStandardOutput())
        + QString::fromUtf8(proc.readAllStandardError());

    // Success looks like "Mounted /dev/sda2 at /media/roohaniye/<label>."
    // Already-mounted-by-something-else looks similar or mentions
    // AlreadyMounted - either way, don't trust our own string parsing as
    // the final word; re-verify via QStorageInfo below.
    static const QRegularExpression atRe(QStringLiteral("at\\s+(\\S+?)\\.?\\s*$"));
    const QRegularExpressionMatch match = atRe.match(combined.trimmed());
    if (match.hasMatch()) {
        const QString mountedPath = match.captured(1);
        const QStorageInfo info(mountedPath);
        if (info.isValid() && info.rootPath() == mountedPath)
            return mountedPath;
    }

    // Fallback: scan currently mounted volumes for this device, in case the
    // udisksctl message format didn't match (e.g. it was already mounted by
    // something else moments earlier).
    const auto allVolumes = QStorageInfo::mountedVolumes();
    for (const QStorageInfo &info : allVolumes) {
        if (QString::fromUtf8(info.device()) == devicePath)
            return info.rootPath();
    }

    return QString();
}

QString DebugBackend::findOrMountUsbDrive() const
{
    // Don't rely on a desktop auto-mount daemon (gvfs/udisksd via a full
    // session) having already mounted the stick under /media/$USER - this
    // kiosk shell doesn't run a full desktop session, so that daemon may
    // simply not be present. Instead, walk /sys/block ourselves to find
    // removable disks, then mount the first unmounted partition we find
    // via udisksctl (same unprivileged path as the internal-disk retry).
    QDir sysBlock("/sys/block");
    const QFileInfoList disks = sysBlock.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot);

    for (const QFileInfo &diskInfo : disks) {
        const QString diskName = diskInfo.fileName(); // e.g. "sda"
        if (diskName.startsWith("loop") || diskName.startsWith("nvme") || diskName.startsWith("dm-"))
            continue; // never treat loop devices, dm devices, or the internal NVMe as "USB"

        QFile removableFlag("/sys/block/" + diskName + "/removable");
        if (!removableFlag.open(QIODevice::ReadOnly))
            continue;
        const bool isRemovable = removableFlag.readAll().trimmed() == "1";
        removableFlag.close();
        if (!isRemovable)
            continue;

        // Look for partitions of this disk (e.g. sda1, sda2, ...); if none
        // exist, fall back to the whole-disk device itself.
        QDir diskDir("/sys/block/" + diskName);
        const QFileInfoList children = diskDir.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot);
        QStringList candidates;
        for (const QFileInfo &child : children) {
            if (child.fileName().startsWith(diskName))
                candidates << ("/dev/" + child.fileName());
        }
        if (candidates.isEmpty())
            candidates << ("/dev/" + diskName);

        for (const QString &devicePath : candidates) {
            if (!QFileInfo::exists(devicePath))
                continue;

            // Already mounted somewhere? Use that mountpoint directly.
            const auto allVolumes = QStorageInfo::mountedVolumes();
            QString mountedAt;
            for (const QStorageInfo &info : allVolumes) {
                if (QString::fromUtf8(info.device()) == devicePath) {
                    mountedAt = info.rootPath();
                    break;
                }
            }
            if (mountedAt.isEmpty())
                mountedAt = runUdisksctlMount(devicePath);

            if (!mountedAt.isEmpty())
                return mountedAt;
        }
    }

    return QString(); // no removable USB/SD disk found at all
}

QVariantList DebugBackend::listLogTargetDisks() const
{
    QVariantList result;

    // 1. Every currently-detected removable USB/SD device.
    if (m_storageBackend) {
        const QVariantList devices = m_storageBackend->devices();
        for (const QVariant &dev : devices) {
            const QVariantMap m = dev.toMap();
            QVariantMap entry;
            entry["label"] = m.value("label").toString() + " (USB/SD)";
            entry["path"] = m.value("path").toString();
            entry["removable"] = true;
            result.append(entry);
        }
    }

    // 3. USB/SD fallback via our own mount + a fixed, predictable path.
    // Don't rely solely on StorageBackend's gvfs/udisksd auto-mount
    // detection above (item 1) - if no desktop auto-mount daemon is
    // running in this kiosk session, that list stays empty even with a
    // stick plugged in. Actively find + mount one ourselves, then expose
    // it at a stable "<home>/usb" symlink so it's always the same path
    // regardless of the drive's label or where udisksctl actually mounted
    // it (typically /media/<user>/<label>).
    {
        const QString usbMountPoint = findOrMountUsbDrive();
        if (!usbMountPoint.isEmpty()) {
            const QString home = QStandardPaths::writableLocation(QStandardPaths::HomeLocation);
            if (!home.isEmpty()) {
                const QString usbLinkPath = home + "/usb";
                QFileInfo linkInfo(usbLinkPath);
                // Refresh the symlink every time in case a different stick
                // is now plugged in than last time this was called.
                if (linkInfo.isSymLink() || linkInfo.exists())
                    QFile::remove(usbLinkPath);
                if (QFile::link(usbMountPoint, usbLinkPath)) {
                    QVariantMap entry;
                    entry["label"] = "USB drive (" + usbLinkPath + ")";
                    entry["path"] = usbLinkPath;
                    entry["removable"] = true;
                    result.append(entry);
                }
            }
        }
    }

    // 4. The internal disk, if mount-internal-disk.service (or the
    // debug-console.sh fallback) has it mounted - this is the live-boot/
    // kiosk case, distinct from just running this binary on a normal
    // desktop session. IMPORTANT: check it's an actual distinct
    // mountpoint via QStorageInfo, not just QFileInfo::exists() - the
    // systemd unit does `mkdir -p /mnt/internal-disk` unconditionally
    // even when its mount command fails, so the directory always exists
    // regardless of whether anything real is actually mounted there.
    // Trusting bare existence would silently offer an empty ephemeral
    // folder as if it were the real persistent disk.
    const QString internalMount = findInternalDiskMountPoint();
    if (!internalMount.isEmpty()) {
        // 4a. The exact pre-created, chmod-777 subfolder
        // (mount-internal-disk.service always makes this one specific
        // path writable - see that unit for why) - surfaced as its own
        // top-of-list, clearly-labeled entry so it's a single tap
        // instead of something the user has to browse into and guess
        // correctly. Without this, "Internal disk" alone just opens the
        // real filesystem root, and every OTHER folder under it (like
        // another Linux user's home directory) looks equally pickable
        // even though only this one specific path actually accepts
        // writes from the unprivileged roohaniye account.
        const QString recommended = internalMount + "/roohaniye-debug-logs";
        QDir().mkpath(recommended); // defensive - should already exist via the systemd unit
        QVariantMap recommendedEntry;
        recommendedEntry["label"] = "\u2713 Recommended: Internal disk logs folder";
        recommendedEntry["path"] = recommended;
        recommendedEntry["removable"] = false;
        result.append(recommendedEntry);

        QVariantMap entry;
        entry["label"] = "Internal disk (browse manually)";
        entry["path"] = internalMount;
        entry["removable"] = false;
        result.append(entry);
    }

    // 3. This device's home folder - always available, covers the
    // normal-desktop dev/testing case where neither of the above apply.
    // On a live-boot ISO session (Ubuntu's casper live user is normally
    // "ubuntu", not the real desktop account), this resolves to a home
    // directory living in the live session's RAM overlay - anything
    // saved there vanishes on reboot, same as the internal disk not
    // being mounted. Detect that case via the root filesystem type and
    // say so plainly in the label, so it's never silently mistaken for
    // persistent storage again.
    const QString home = QStandardPaths::writableLocation(QStandardPaths::HomeLocation);
    if (!home.isEmpty()) {
        const QStorageInfo rootInfo(QStringLiteral("/"));
        const QByteArray fsType = rootInfo.fileSystemType().toLower();
        const bool looksLikeLiveSession = fsType.contains("overlay") || fsType.contains("aufs") || fsType.contains("squashfs");
        QVariantMap entry;
        entry["label"] = looksLikeLiveSession
            ? ("This device's home folder (" + home + ") - \u26A0 TEMPORARY, live USB session, will NOT survive reboot")
            : "This device's home folder";
        entry["path"] = home;
        entry["removable"] = false;
        result.append(entry);
    }

    return result;
}

QVariantList DebugBackend::listFolders(const QString &path) const
{
    QVariantList result;
    QDir dir(path);
    if (!dir.exists())
        return result;

    const QFileInfoList entries = dir.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name);
    for (const QFileInfo &fi : entries) {
        QVariantMap entry;
        entry["name"] = fi.fileName();
        entry["path"] = fi.absoluteFilePath();
        result.append(entry);
    }
    return result;
}

QVariantMap DebugBackend::checkFolderAccess(const QString &path) const
{
    QVariantMap result;
    QFileInfo pathInfo(path);

    if (!pathInfo.exists()) {
        result["ok"] = false;
        result["reason"] = "This folder doesn't exist.";
        result["folders"] = QVariantList();
        return result;
    }

    // A directory needs BOTH read (to list entries) and execute (to stat
    // into them / traverse) permission - e.g. /home/bismillah is mode 750
    // owned by a different uid, so roohaniye has neither here. Checking
    // this explicitly is the only way to tell "permission denied" apart
    // from "genuinely empty folder" - QDir::entryInfoList() returns an
    // empty list in both cases with no error signal at all.
    if (!pathInfo.isReadable() || !pathInfo.isExecutable()) {
        result["ok"] = false;
        result["reason"] = QString(
            "Permission denied - this folder belongs to a different user "
            "account and roohaniye can't read into it. This is normal Linux "
            "file permissions, not an app bug. (owner: %1, permissions: %2)")
            .arg(pathInfo.owner())
            .arg(QString::number(pathInfo.permissions(), 8));
        result["folders"] = QVariantList();
        return result;
    }

    result["ok"] = true;
    result["reason"] = QString();
    result["folders"] = listFolders(path);
    return result;
}

QString DebugBackend::createFolder(const QString &parentPath, const QString &name)
{
    if (name.trimmed().isEmpty())
        return QString();

    QDir dir(parentPath);
    if (!dir.exists())
        return QString();

    if (!dir.mkdir(name))
        return QString();

    return dir.absoluteFilePath(name);
}

void DebugBackend::selectLogDirectory(const QString &dir)
{
    if (dir.isEmpty())
        return;

    QDir().mkpath(dir);
    m_selectedLogDir = dir;
    m_logFilePath.clear(); // force ensureLogFile() to start a fresh log under the new dir
    emit logFilePathChanged();
}

QVariantMap DebugBackend::trySelectLogDirectory(const QString &dir)
{
    QVariantMap result;

    if (dir.isEmpty()) {
        result["ok"] = false;
        result["reason"] = "No folder given.";
        return result;
    }

    // Real write-probe, same one ensureLogFile()'s auto-detect chain uses -
    // this is the actual test that matters, not just QFileInfo permission
    // bits (which can't be created ahead of time on a path that doesn't
    // exist yet, e.g. a brand-new folder name that hasn't been mkdir'd).
    if (!dirIsActuallyWritable(dir)) {
        QFileInfo info(dir);
        result["ok"] = false;
        if (info.exists()) {
            // Same message shape as checkFolderAccess() for consistency -
            // this is the "picked a folder you can't write into" case,
            // e.g. another Linux user's home directory.
            result["reason"] = QString(
                "Can't save logs here - this folder belongs to a different "
                "user account and roohaniye doesn't have write access. "
                "(owner: %1, permissions: %2)")
                .arg(info.owner())
                .arg(QString::number(info.permissions(), 8));
        } else {
            result["reason"] = "Couldn't create or write to this folder.";
        }
        // Deliberately does NOT touch m_selectedLogDir or m_logFilePath -
        // the previous (working) selection, if any, stays in effect rather
        // than being silently replaced by a broken one.
        return result;
    }

    m_selectedLogDir = dir;
    m_logFilePath.clear(); // force ensureLogFile() to start a fresh log under the new dir
    emit logFilePathChanged();

    result["ok"] = true;
    result["reason"] = QString();
    return result;
}
