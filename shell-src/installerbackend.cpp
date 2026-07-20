#include "installerbackend.h"
#include "authbackend.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QProcess>
#include <QSettings>
#include <QStandardPaths>
#include <QTemporaryFile>
#include <QTextStream>
#include <QThread>
#include <QDebug>
#include <QVector>
#include <QPair>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QJsonValue>

namespace {
const char *kMarkerPath = "/opt/roohaniye/data/.installed";
}

InstallerBackend::InstallerBackend(QObject *parent) : QObject(parent) {}

bool InstallerBackend::isInstalled() const
{
    return QFile::exists(QString::fromLatin1(kMarkerPath));
}

QString InstallerBackend::findRootDisk() const
{
    // findmnt -no SOURCE / -> e.g. /dev/sda3 ; strip the partition
    // suffix down to the parent disk device (sda3 -> sda, nvme0n1p2 ->
    // nvme0n1, mmcblk0p1 -> mmcblk0).
    QProcess p;
    p.start("findmnt", {"-no", "SOURCE", "/"});
    if (!p.waitForFinished(3000)) return QString();
    const QString src = QString::fromUtf8(p.readAllStandardOutput()).trimmed();
    qDebug() << "InstallerBackend::findRootDisk: findmnt SOURCE / ->" << src;
    if (src.isEmpty() || !src.startsWith("/dev/")) {
        qDebug() << "InstallerBackend::findRootDisk: not a /dev/ path (likely overlay on a live boot) - excluding nothing";
        return QString();
    }

    QString name = src.mid(5); // strip "/dev/"
    // nvme0n1p3 / mmcblk0p1 style: strip trailing "pN"
    if (name.contains("nvme") || name.contains("mmcblk")) {
        int idx = name.lastIndexOf('p');
        if (idx > 0) {
            bool ok = false;
            name.mid(idx + 1).toInt(&ok);
            if (ok) name = name.left(idx);
        }
    } else {
        // sdaN / vdaN style: strip trailing digits
        int i = name.length();
        while (i > 0 && name.at(i - 1).isDigit()) --i;
        name = name.left(i);
    }
    const QString result = "/dev/" + name;
    qDebug() << "InstallerBackend::findRootDisk: resolved root disk ->" << result;
    return result;
}

namespace {
// Human-readable size label shared by listDisks()/listDirectory().
QString humanSize(qint64 bytes)
{
    if (bytes < 1024LL * 1024 * 1024)
        return QString::number(bytes / (1024.0 * 1024.0), 'f', 0) + " MB";
    return QString::number(bytes / (1024.0 * 1024.0 * 1024.0), 'f', 1) + " GB";
}

// lsblk SIZE with -b is plain bytes as a JSON number/string depending on
// version; handle both.
qint64 jsonSizeBytes(const QJsonValue &v)
{
    if (v.isDouble()) return static_cast<qint64>(v.toDouble());
    return v.toString().toLongLong();
}
}

QVariantList InstallerBackend::listDisks() const
{
    QVariantList result;
    const QString rootDisk = findRootDisk();

    QProcess p;
    // No -d this time: we want the partition ("children") tree too, so
    // we can warn about existing partitions/encryption/other OSes
    // before the user picks a disk to erase. -b: bytes for size, -J:
    // JSON (far more robust to parse than the old fixed-column output,
    // which broke whenever MODEL contained embedded spaces).
    p.start("lsblk", {"-J", "-b", "-o", "NAME,SIZE,MODEL,TRAN,RM,TYPE,PTTYPE,FSTYPE,LABEL"});
    if (!p.waitForFinished(5000)) {
        qWarning() << "InstallerBackend::listDisks: lsblk failed to run";
        return result;
    }
    if (p.exitCode() != 0) {
        qWarning() << "InstallerBackend::listDisks: lsblk exited" << p.exitCode();
        return result;
    }

    QJsonParseError perr;
    const QJsonDocument doc = QJsonDocument::fromJson(p.readAllStandardOutput(), &perr);
    if (perr.error != QJsonParseError::NoError || !doc.isObject()) {
        qWarning() << "InstallerBackend::listDisks: failed to parse lsblk JSON:" << perr.errorString();
        return result;
    }

    const QJsonArray devices = doc.object().value("blockdevices").toArray();
    qDebug() << "InstallerBackend::listDisks: lsblk reports" << devices.size() << "block devices total, rootDisk to exclude =" << rootDisk;
    for (const QJsonValue &dv : devices) {
        const QJsonObject obj = dv.toObject();
        if (obj.value("type").toString() != "disk") continue; // skip loop/rom/etc

        const QString name = obj.value("name").toString();
        const QString path = "/dev/" + name;
        if (!rootDisk.isEmpty() && path == rootDisk) {
            qDebug() << "InstallerBackend::listDisks: excluding" << path << "(matches root disk)";
            continue; // never offer the running disk
        }

        const qint64 bytes = jsonSizeBytes(obj.value("size"));
        if (bytes <= 0) continue;

        const QString tran = obj.value("tran").toString();
        const QString model = obj.value("model").toString();
        const bool removable = obj.value("rm").toBool();
        const QString pttype = obj.value("pttype").toString(); // "gpt"/"dos"/"" (blank disk)

        const QJsonArray children = obj.value("children").toArray();
        const int partitionCount = children.size();
        bool hasEncryption = false;
        bool hasBitlocker = false;
        bool hasWindows = false;
        bool hasOtherLinux = false;

        for (const QJsonValue &cv : children) {
            const QJsonObject part = cv.toObject();
            const QString fstype = part.value("fstype").toString().toLower();
            if (fstype == "crypto_luks") hasEncryption = true;
            else if (fstype == "bitlocker") hasBitlocker = true;
            else if (fstype == "ntfs") hasWindows = true;
            else if (fstype == "ext4" || fstype == "ext3" || fstype == "btrfs" || fstype == "xfs")
                hasOtherLinux = true;
        }

        QVariantList warnings;
        if (partitionCount > 0) {
            warnings.append(QString("Disk has %1 existing partition(s) - ALL data will be permanently erased")
                                 .arg(partitionCount));
        }
        if (hasEncryption)
            warnings.append(QStringLiteral("Contains an encrypted (LUKS) partition"));
        if (hasBitlocker)
            warnings.append(QStringLiteral("Contains a BitLocker-encrypted Windows partition"));
        if (hasWindows)
            warnings.append(QStringLiteral("An existing Windows (NTFS) installation was detected"));
        if (hasOtherLinux)
            warnings.append(QStringLiteral("An existing Linux installation was detected"));

        QVariantMap dev;
        dev["path"] = path;
        dev["name"] = name;
        dev["sizeLabel"] = humanSize(bytes);
        dev["sizeBytes"] = bytes;
        dev["model"] = model.isEmpty() ? QStringLiteral("Unknown disk") : model;
        dev["transport"] = tran.isEmpty() ? QStringLiteral("unknown") : tran;
        dev["isRemovable"] = removable;
        dev["partitionTableType"] = pttype.isEmpty() ? QStringLiteral("none") : pttype;
        dev["partitionCount"] = partitionCount;
        dev["isBlank"] = (partitionCount == 0 && pttype.isEmpty());
        dev["hasEncryption"] = (hasEncryption || hasBitlocker);
        dev["warnings"] = warnings;
        result.append(dev);
    }
    qDebug() << "InstallerBackend::listDisks: returning" << result.size() << "eligible disk(s)";
    return result;
}

QVariantList InstallerBackend::listFreeSpace(const QString &diskPath) const
{
    QVariantList result;
    QProcess p;
    p.start("parted", {"-m", "-s", diskPath, "unit", "MiB", "print", "free"});
    if (!p.waitForFinished(6000)) {
        qWarning() << "InstallerBackend::listFreeSpace: parted timed out for" << diskPath;
        return result;
    }
    if (p.exitCode() != 0) {
        qWarning() << "InstallerBackend::listFreeSpace: parted exited" << p.exitCode() << "for" << diskPath;
        return result;
    }

    // parted -m output looks like:
    //   BYT;
    //   /dev/sda:512110MiB:nvme:512:512:gpt:...;
    //   1:1.00MiB:513MiB:512MiB:fat32:ESP:boot, esp;
    //   1:513MiB:8513MiB:8000MiB:free;      <- free regions have no fs
    //   2:8513MiB:512110MiB:503597MiB:ext4::;
    // Free regions are identified by field[4] == "free" (they have no
    // partition number in some parted versions, a placeholder in
    // others - don't rely on field[0], just check the fstype field).
    const QStringList lines = QString::fromUtf8(p.readAllStandardOutput()).split('\n', Qt::SkipEmptyParts);
    const qint64 kMinFreeMiB = 2048; // ignore slivers under ~2GiB - not enough for a usable install
    for (const QString &rawLine : lines) {
        QString line = rawLine.trimmed();
        if (line.endsWith(';')) line.chop(1);
        const QStringList f = line.split(':');
        if (f.size() < 5) continue;
        if (!f.at(4).trimmed().contains("free", Qt::CaseInsensitive)) continue;

        auto miB = [](QString s) -> double {
            s.remove("MiB");
            bool ok = false;
            const double v = s.toDouble(&ok);
            return ok ? v : -1.0;
        };
        const double startMiB = miB(f.at(1));
        const double endMiB = miB(f.at(2));
        if (startMiB < 0 || endMiB < 0 || endMiB <= startMiB) continue;

        const qint64 sizeMiB = static_cast<qint64>(endMiB - startMiB);
        if (sizeMiB < kMinFreeMiB) continue;

        QVariantMap region;
        region["startMiB"] = static_cast<qint64>(startMiB);
        region["endMiB"] = static_cast<qint64>(endMiB);
        region["sizeMiB"] = sizeMiB;
        region["sizeLabel"] = sizeMiB >= 1024
            ? QString::number(sizeMiB / 1024.0, 'f', 1) + " GB"
            : QString::number(sizeMiB) + " MB";
        result.append(region);
    }
    qDebug() << "InstallerBackend::listFreeSpace:" << diskPath << "->" << result.size() << "usable free region(s)";
    return result;
}

QVariantList InstallerBackend::listDirectory(const QString &path) const
{
    QVariantList result;
    QString target = path.isEmpty() ? QStringLiteral("/media") : path;

    QDir dir(target);
    if (!dir.exists()) return result;

    const QFileInfoList entries = dir.entryInfoList(
        QDir::Dirs | QDir::Files | QDir::NoDotAndDotDot,
        QDir::DirsFirst | QDir::Name);

    for (const QFileInfo &fi : entries) {
        QVariantMap item;
        item["name"] = fi.fileName();
        item["path"] = fi.absoluteFilePath();
        item["isDir"] = fi.isDir();
        const QString suf = fi.suffix().toLower();
        item["isDb"] = !fi.isDir() && (suf == "db" || suf == "sqlite" || suf == "sqlite3");
        item["isJson"] = !fi.isDir() && suf == "json";

        if (!fi.isDir()) {
            const qint64 bytes = fi.size();
            if (bytes < 1024 * 1024)
                item["sizeLabel"] = QString("%1 KB").arg(bytes / 1024);
            else if (bytes < 1024LL * 1024 * 1024)
                item["sizeLabel"] = QString::number(bytes / (1024.0 * 1024.0), 'f', 1) + " MB";
            else
                item["sizeLabel"] = QString::number(bytes / (1024.0 * 1024.0 * 1024.0), 'f', 2) + " GB";
        } else {
            item["sizeLabel"] = "";
        }
        result.append(item);
    }
    return result;
}

QString InstallerBackend::buildFreeSpacePartitionCommands(const QString &diskPath, qint64 startMiB, qint64 endMiB,
                                                           const QVariantList &partitions,
                                                           QString &outRootPart, QString &outEfiPart,
                                                           QString &outHomePart, QString &outSwapPart,
                                                           QString &error) const
{
    // Figure out the next free partition NUMBER on this disk (existing
    // partitions are left completely alone - we only ever append new
    // ones after them).
    QProcess lp;
    lp.start("lsblk", {"-n", "-o", "NAME", diskPath});
    lp.waitForFinished(5000);
    const int existingCount = qMax(0, QString::fromUtf8(lp.readAllStandardOutput())
                                           .split('\n', Qt::SkipEmptyParts).size() - 1);
    const bool needsP = diskPath.contains("nvme") || diskPath.contains("mmcblk");
    auto partPath = [&](int num) { return diskPath + (needsP ? "p" : "") + QString::number(num); };

    // Validate the requested partition list.
    QVariantList parts = partitions;
    if (parts.isEmpty()) {
        QVariantMap rootOnly; rootOnly["mountPoint"] = "/"; rootOnly["sizeMiB"] = -1;
        parts.append(rootOnly);
    }
    bool hasRoot = false;
    int fillCount = 0;
    for (int i = 0; i < parts.size(); ++i) {
        const QVariantMap m = parts.at(i).toMap();
        const QString mp = m.value("mountPoint").toString();
        if (mp != "/" && mp != "/home" && mp != "swap") {
            error = "Invalid partition mount point: " + mp;
            return QString();
        }
        if (mp == "/") hasRoot = true;
        const qint64 sz = m.value("sizeMiB", -1).toLongLong();
        if (sz <= 0) {
            fillCount++;
            if (i != parts.size() - 1) {
                error = "Only the last partition in the list may use remaining space.";
                return QString();
            }
        }
    }
    if (!hasRoot) { error = "A root (/) partition is required."; return QString(); }
    if (fillCount > 1) { error = "Only one partition may use remaining space."; return QString(); }

    const qint64 kEspSizeMiB = 512;
    const qint64 regionSizeMiB = endMiB - startMiB;
    qint64 explicitTotal = kEspSizeMiB;
    for (const QVariant &v : parts) {
        const qint64 sz = v.toMap().value("sizeMiB", -1).toLongLong();
        if (sz > 0) explicitTotal += sz;
    }
    if (explicitTotal > regionSizeMiB) {
        error = "Selected partitions don't fit in the chosen free-space region.";
        return QString();
    }

    QString cmds;
    QTextStream out(&cmds);

    qint64 cursor = startMiB;
    int partNum = existingCount + 1;

    // ESP first, always.
    out << "parted -s " << diskPath << " mkpart ESP fat32 " << cursor << "MiB " << (cursor + kEspSizeMiB) << "MiB\n";
    out << "parted -s " << diskPath << " set " << partNum << " esp on\n";
    outEfiPart = partPath(partNum);
    cursor += kEspSizeMiB;
    partNum++;

    for (int i = 0; i < parts.size(); ++i) {
        const QVariantMap m = parts.at(i).toMap();
        const QString mp = m.value("mountPoint").toString();
        qint64 sz = m.value("sizeMiB", -1).toLongLong();
        const bool isFill = (sz <= 0);
        const qint64 partEnd = isFill ? endMiB : (cursor + sz);

        const QString label = (mp == "/") ? "root" : (mp == "/home" ? "home" : "swap");
        const QString fsHint = (mp == "swap") ? "linux-swap" : "ext4";
        out << "parted -s " << diskPath << " mkpart " << label << " " << fsHint << " "
            << cursor << "MiB " << partEnd << "MiB\n";

        const QString devPath = partPath(partNum);
        if (mp == "/") outRootPart = devPath;
        else if (mp == "/home") outHomePart = devPath;
        else outSwapPart = devPath;

        cursor = partEnd;
        partNum++;
    }

    return cmds;
}

QString InstallerBackend::buildInstallScript(const QVariantMap &options, QString &error) const
{
    const QString diskPath = options.value("diskPath").toString();
    const QVariantList extraDbs = options.value("extraDatabases").toList();

    // Re-validate diskPath against the real, current disk list - never
    // trust a path the QML side merely remembered from an earlier call.
    bool diskValid = false;
    for (const QVariant &v : listDisks()) {
        if (v.toMap().value("path").toString() == diskPath) { diskValid = true; break; }
    }
    if (!diskValid) {
        error = "Selected disk is not a valid, currently-available target.";
        return QString();
    }

    // Figure out the partition-name pattern for this disk (nvme/mmcblk
    // need a "p" before the partition number, sd/vd don't).
    const QString diskName = QFileInfo(diskPath).fileName();
    const bool needsP = diskName.contains("nvme") || diskName.contains("mmcblk");

    const QString installMode = options.value("installMode", "erase").toString();

    QString part1;      // EFI
    QString part2;      // root
    QString homePart;   // optional
    QString swapPart;   // optional
    QString stage1;      // partitioning + formatting + mounting, mode-specific

    QTextStream stage1Out(&stage1);

    if (installMode == "erase") {
        part1 = diskPath + (needsP ? "p1" : "1");
        part2 = diskPath + (needsP ? "p2" : "2");

        stage1Out << "echo STAGE:partitioning\n";
        // Wipe partition table, create GPT with a 512MB EFI partition and
        // the rest as the root partition.
        stage1Out << "wipefs -a " << diskPath << "\n";
        stage1Out << "parted -s " << diskPath << " mklabel gpt\n";
        stage1Out << "parted -s " << diskPath << " mkpart ESP fat32 1MiB 513MiB\n";
        stage1Out << "parted -s " << diskPath << " set 1 esp on\n";
        stage1Out << "parted -s " << diskPath << " mkpart root ext4 513MiB 100%\n";
        stage1Out << "partprobe " << diskPath << "\n";
        stage1Out << "sleep 2\n";

        stage1Out << "echo STAGE:formatting\n";
        stage1Out << "mkfs.fat -F32 " << part1 << "\n";
        stage1Out << "mkfs.ext4 -F " << part2 << "\n";
    } else if (installMode == "alongside" || installMode == "manual") {
        // NEVER wipes the disk or touches its existing partitions - only
        // ever creates new ones inside a free-space region the caller
        // picked, re-validated here against a fresh listFreeSpace() call.
        const qint64 startMiB = options.value("freeSpaceStartMiB", -1).toLongLong();
        const qint64 endMiB = options.value("freeSpaceEndMiB", -1).toLongLong();
        bool regionValid = false;
        for (const QVariant &v : listFreeSpace(diskPath)) {
            const QVariantMap r = v.toMap();
            if (r.value("startMiB").toLongLong() <= startMiB && r.value("endMiB").toLongLong() >= endMiB
                && startMiB < endMiB) {
                regionValid = true;
                break;
            }
        }
        if (!regionValid) {
            error = "Selected free-space region is no longer valid - refresh and try again.";
            return QString();
        }

        QVariantList partitions = options.value("partitions").toList();
        if (installMode == "alongside") {
            // Fixed layout: ESP + a single ext4 root filling the rest.
            QVariantMap rootOnly; rootOnly["mountPoint"] = "/"; rootOnly["sizeMiB"] = -1;
            partitions = QVariantList{ rootOnly };
        }

        QString partErr;
        const QString partCmds = buildFreeSpacePartitionCommands(
            diskPath, startMiB, endMiB, partitions, part2, part1, homePart, swapPart, partErr);
        if (!partErr.isEmpty()) {
            error = partErr;
            return QString();
        }

        stage1Out << "echo STAGE:partitioning\n";
        stage1Out << partCmds;
        stage1Out << "partprobe " << diskPath << "\n";
        stage1Out << "sleep 2\n";

        stage1Out << "echo STAGE:formatting\n";
        stage1Out << "mkfs.fat -F32 " << part1 << "\n";
        stage1Out << "mkfs.ext4 -F " << part2 << "\n";
        if (!homePart.isEmpty()) stage1Out << "mkfs.ext4 -F " << homePart << "\n";
        if (!swapPart.isEmpty()) stage1Out << "mkswap " << swapPart << "\n";
    } else {
        error = "Unknown installMode: " + installMode;
        return QString();
    }

    QString script;
    QTextStream out(&script);
    out << "#!/bin/sh\n";
    out << "set -e\n";
    out << stage1;

    out << "echo STAGE:cloning\n";
    out << "mkdir -p /mnt/roohaniye-target\n";
    out << "mount " << part2 << " /mnt/roohaniye-target\n";
    out << "mkdir -p /mnt/roohaniye-target/boot/efi\n";
    out << "mount " << part1 << " /mnt/roohaniye-target/boot/efi\n";
    if (!homePart.isEmpty()) {
        out << "mkdir -p /mnt/roohaniye-target/home\n";
        out << "mount " << homePart << " /mnt/roohaniye-target/home\n";
    }
    if (!swapPart.isEmpty()) {
        out << "swapon " << swapPart << " || true\n";
    }
    // Clone the currently-running live filesystem onto the target,
    // excluding pseudo-filesystems, the target mount itself, and the
    // live boot media.
    out << "rsync -aAX --info=progress2 "
        << "--exclude=/proc/* --exclude=/sys/* --exclude=/dev/* "
        << "--exclude=/run/* --exclude=/tmp/* --exclude=/mnt/* "
        << "--exclude=/media/* --exclude=/lost+found "
        << "/ /mnt/roohaniye-target/\n";
    out << "mkdir -p /mnt/roohaniye-target/proc /mnt/roohaniye-target/sys "
           "/mnt/roohaniye-target/dev /mnt/roohaniye-target/run\n";

    out << "echo STAGE:databases\n";
    out << "mkdir -p /mnt/roohaniye-target/opt/roohaniye/data\n";
    for (const QVariant &v : extraDbs) {
        const QVariantMap m = v.toMap();
        const QString src = m.value("sourcePath").toString();
        const QString targetFile = m.value("targetFile").toString();
        // Only allow the three known target filenames - never let
        // targetFile become an arbitrary path.
        if (targetFile != "quran_text.db" && targetFile != "quran_audio.db"
            && targetFile != "hadiths.db") {
            continue;
        }
        if (src.isEmpty() || !QFile::exists(src)) continue;
        out << "cp -f '" << src.toHtmlEscaped().replace("'", "'\\''")
            << "' /mnt/roohaniye-target/opt/roohaniye/data/" << targetFile << "\n";
    }
    // Optional account: `accountsStagingPath` was already written (as a
    // real accounts.dat, PBKDF2 hash + salt only, no plaintext) by
    // startInstall() before this script was generated - just copy it
    // into place and lock down its permissions, same as AuthBackend
    // does for the live session's own accounts.dat.
    const QString accountsStagingPath = options.value("accountsStagingPath").toString();
    if (!accountsStagingPath.isEmpty() && QFile::exists(accountsStagingPath)) {
        out << "cp -f '" << accountsStagingPath.toHtmlEscaped().replace("'", "'\\''")
            << "' /mnt/roohaniye-target/opt/roohaniye/data/accounts.dat\n";
        out << "chmod 600 /mnt/roohaniye-target/opt/roohaniye/data/accounts.dat\n";
    }

    // Mark this target disk as installed so the installer never offers
    // itself again once it boots for real.
    out << "mkdir -p /mnt/roohaniye-target$(dirname " << kMarkerPath << ")\n";
    out << "date -Iseconds > /mnt/roohaniye-target" << kMarkerPath << "\n";

    out << "echo STAGE:bootloader\n";
    if (installMode != "erase") {
        // Erase mode relies on whatever /etc/fstab was cloned from the
        // live session (a pre-existing limitation, out of scope here -
        // see build.md). But alongside/manual introduce NEW partitions
        // (home/swap/a second ESP) that the cloned fstab knows nothing
        // about, so without this they'd silently stop being mounted on
        // the very next boot. Write fresh UUID-based entries for
        // everything we just created.
        out << "EFI_UUID=$(blkid -s UUID -o value " << part1 << ")\n";
        out << "ROOT_UUID=$(blkid -s UUID -o value " << part2 << ")\n";
        out << "echo \"UUID=$ROOT_UUID / ext4 defaults 0 1\" >> /mnt/roohaniye-target/etc/fstab\n";
        out << "echo \"UUID=$EFI_UUID /boot/efi vfat umask=0077 0 1\" >> /mnt/roohaniye-target/etc/fstab\n";
        if (!homePart.isEmpty()) {
            out << "HOME_UUID=$(blkid -s UUID -o value " << homePart << ")\n";
            out << "echo \"UUID=$HOME_UUID /home ext4 defaults 0 2\" >> /mnt/roohaniye-target/etc/fstab\n";
        }
        if (!swapPart.isEmpty()) {
            out << "SWAP_UUID=$(blkid -s UUID -o value " << swapPart << ")\n";
            out << "echo \"UUID=$SWAP_UUID none swap sw 0 0\" >> /mnt/roohaniye-target/etc/fstab\n";
        }
    }
    out << "for d in /dev /dev/pts /proc /sys /run; do "
           "mount --bind $d /mnt/roohaniye-target$d; done\n";
    out << "chroot /mnt/roohaniye-target grub-install --target=x86_64-efi "
           "--efi-directory=/boot/efi --bootloader-id=RoohaniyeNooreIlm "
        << diskPath << " || chroot /mnt/roohaniye-target grub-install " << diskPath << "\n";
    out << "chroot /mnt/roohaniye-target update-grub || true\n";

    // Autologin + autostart straight into roohaniye-shell fullscreen,
    // mirroring however the live session itself boots into the shell -
    // written as a systemd unit so it survives desktop-environment
    // differences on the base live image.
    out << "cat > /mnt/roohaniye-target/etc/systemd/system/roohaniye-shell.service << 'UNITEOF'\n";
    out << "[Unit]\n";
    out << "Description=RoohaniyeNooreIlm Shell\n";
    out << "After=graphical.target\n\n";
    out << "[Service]\n";
    out << "ExecStart=/opt/roohaniye/bin/roohaniye-shell\n";
    out << "Restart=always\n";
    out << "User=root\n";
    out << "Environment=QT_QPA_PLATFORM=eglfs\n\n";
    out << "[Install]\n";
    out << "WantedBy=graphical.target\n";
    out << "UNITEOF\n";
    out << "chroot /mnt/roohaniye-target systemctl enable roohaniye-shell.service\n";

    out << "echo STAGE:finishing\n";
    out << "for d in /dev/pts /dev /proc /sys /run; do "
           "umount -lf /mnt/roohaniye-target$d 2>/dev/null || true; done\n";
    if (!swapPart.isEmpty()) out << "swapoff " << swapPart << " || true\n";
    if (!homePart.isEmpty()) out << "umount " << homePart << "\n";
    out << "umount " << part1 << "\n";
    out << "umount " << part2 << "\n";
    out << "echo STAGE:done\n";

    return script;
}

void InstallerBackend::startInstall(const QVariantMap &options)
{
    if (m_installRunning) {
        emit installFinished(false, "An install is already running.");
        return;
    }

    const QString confirmText = options.value("confirmText").toString();
    if (confirmText != "ERASE") {
        emit installFinished(false, "Confirmation text did not match. Nothing was touched.");
        return;
    }

    // Build the optional account staging file BEFORE the script (which
    // just needs its path). Deliberately does not touch this live
    // session's own accounts.dat - see AuthBackend::exportAccountForInstall.
    QVariantMap effectiveOptions = options;
    const QVariantMap acct = options.value("account").toMap();
    QString accountStagingPath;
    if (!acct.isEmpty()) {
        QVariantMap exported = AuthBackend::exportAccountForInstall(
            acct.value("username").toString(),
            acct.value("password").toString(),
            acct.value("isAdmin").toBool());
        if (!exported.value("ok").toBool()) {
            emit installFinished(false, exported.value("error").toString());
            return;
        }
        auto *acctFile = new QTemporaryFile(QDir::tempPath() + "/roohaniye-install-accounts-XXXXXX.dat");
        acctFile->setAutoRemove(false);
        if (!acctFile->open()) {
            emit installFinished(false, "Could not stage the account file.");
            delete acctFile;
            return;
        }
        accountStagingPath = acctFile->fileName();
        acctFile->close();
        delete acctFile;

        QSettings acctSettings(accountStagingPath, QSettings::IniFormat);
        acctSettings.beginWriteArray("accounts");
        acctSettings.setArrayIndex(0);
        acctSettings.setValue("username", exported.value("username"));
        acctSettings.setValue("salt", exported.value("salt"));
        acctSettings.setValue("hash", exported.value("hash"));
        acctSettings.setValue("isAdmin", exported.value("isAdmin"));
        acctSettings.setValue("recoverySalt", exported.value("recoverySalt"));
        acctSettings.setValue("recoveryHash", exported.value("recoveryHash"));
        acctSettings.endArray();
        acctSettings.sync();

        effectiveOptions["accountsStagingPath"] = accountStagingPath;
        // Shown to the caller now (before the destructive script runs)
        // so the wizard can hold it and reveal it only after
        // installFinished(true, ...) confirms the disk write succeeded.
        emit installAccountRecoveryCode(exported.value("username").toString(),
                                         exported.value("recoveryCode").toString());
    }

    QString error;
    const QString script = buildInstallScript(effectiveOptions, error);
    if (script.isEmpty()) {
        if (!accountStagingPath.isEmpty()) QFile::remove(accountStagingPath);
        emit installFinished(false, error.isEmpty() ? "Could not build install script." : error);
        return;
    }

    auto *scriptFile = new QTemporaryFile(QDir::tempPath() + "/roohaniye-install-XXXXXX.sh", this);
    scriptFile->setAutoRemove(false);
    if (!scriptFile->open()) {
        if (!accountStagingPath.isEmpty()) QFile::remove(accountStagingPath);
        emit installFinished(false, "Could not write install script to disk.");
        delete scriptFile;
        return;
    }
    scriptFile->write(script.toUtf8());
    scriptFile->close();
    const QString scriptPath = scriptFile->fileName();

    m_installRunning = true;
    emit installRunningChanged();
    emit installLog("Install script written to " + scriptPath);
    emit installProgress(0, "partitioning", "Starting...");

    m_proc = new QProcess(this);
    m_proc->setProgram("pkexec");
    m_proc->setArguments({"sh", scriptPath});

    // Rough percent-per-stage mapping for the progress screen; exact
    // per-file rsync progress is logged raw but not parsed into percent
    // (rsync --info=progress2 output isn't reliably machine-parseable
    // across versions), so cloning holds at a mid-range percent while
    // its log lines stream through.
    static const QVector<QPair<QString, int>> stagePercents = {
        {"partitioning", 5}, {"formatting", 15}, {"cloning", 25},
        {"databases", 70}, {"bootloader", 85}, {"finishing", 95}, {"done", 100}
    };

    connect(m_proc, &QProcess::readyReadStandardOutput, this, [this]() {
        const QStringList lines = QString::fromUtf8(m_proc->readAllStandardOutput())
                                       .split('\n', Qt::SkipEmptyParts);
        for (const QString &line : lines) {
            if (line.startsWith("STAGE:")) {
                const QString stage = line.mid(6).trimmed();
                int pct = 0;
                for (const auto &sp : stagePercents) if (sp.first == stage) pct = sp.second;
                emit installProgress(pct, stage, "");
            } else {
                emit installLog(line);
            }
        }
    });
    connect(m_proc, &QProcess::readyReadStandardError, this, [this]() {
        const QStringList lines = QString::fromUtf8(m_proc->readAllStandardError())
                                       .split('\n', Qt::SkipEmptyParts);
        for (const QString &line : lines) emit installLog(line);
    });
    connect(m_proc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished), this,
            [this, scriptPath, accountStagingPath](int exitCode, QProcess::ExitStatus status) {
        m_installRunning = false;
        emit installRunningChanged();
        QFile::remove(scriptPath);
        if (!accountStagingPath.isEmpty()) QFile::remove(accountStagingPath);
        m_proc->deleteLater();
        m_proc = nullptr;
        if (status == QProcess::NormalExit && exitCode == 0) {
            emit installProgress(100, "done", "");
            emit installFinished(true, QString());
        } else {
            emit installFinished(false, QString("Install script exited with code %1.").arg(exitCode));
        }
    });

    m_proc->start();
}

void InstallerBackend::cancelInstall()
{
    if (!m_installRunning || !m_proc) return;
    m_proc->terminate();
    if (!m_proc->waitForFinished(3000)) m_proc->kill();
    // The finished handler above still fires and does the real cleanup;
    // this just requests it happen promptly.
}

void InstallerBackend::rebootSystem() const
{
    // Try the no-prompt path first (works when the shell user is in the
    // right polkit/systemd group, common on kiosk-style installs); fall
    // back to pkexec if that's rejected.
    int rc = QProcess::execute("systemctl", {"reboot"});
    if (rc != 0) {
        QProcess::execute("pkexec", {"reboot"});
    }
}
