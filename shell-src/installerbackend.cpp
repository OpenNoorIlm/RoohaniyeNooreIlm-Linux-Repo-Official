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
    if (src.isEmpty() || !src.startsWith("/dev/")) return QString();

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
    return "/dev/" + name;
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
    for (const QJsonValue &dv : devices) {
        const QJsonObject obj = dv.toObject();
        if (obj.value("type").toString() != "disk") continue; // skip loop/rom/etc

        const QString name = obj.value("name").toString();
        const QString path = "/dev/" + name;
        if (!rootDisk.isEmpty() && path == rootDisk) continue; // never offer the running disk

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
    const QString part1 = diskPath + (needsP ? "p1" : "1"); // EFI
    const QString part2 = diskPath + (needsP ? "p2" : "2"); // root

    QString script;
    QTextStream out(&script);
    out << "#!/bin/sh\n";
    out << "set -e\n";
    out << "echo STAGE:partitioning\n";
    // Wipe partition table, create GPT with a 512MB EFI partition and
    // the rest as the root partition.
    out << "wipefs -a " << diskPath << "\n";
    out << "parted -s " << diskPath << " mklabel gpt\n";
    out << "parted -s " << diskPath << " mkpart ESP fat32 1MiB 513MiB\n";
    out << "parted -s " << diskPath << " set 1 esp on\n";
    out << "parted -s " << diskPath << " mkpart root ext4 513MiB 100%\n";
    out << "partprobe " << diskPath << "\n";
    out << "sleep 2\n";

    out << "echo STAGE:formatting\n";
    out << "mkfs.fat -F32 " << part1 << "\n";
    out << "mkfs.ext4 -F " << part2 << "\n";

    out << "echo STAGE:cloning\n";
    out << "mkdir -p /mnt/roohaniye-target\n";
    out << "mount " << part2 << " /mnt/roohaniye-target\n";
    out << "mkdir -p /mnt/roohaniye-target/boot/efi\n";
    out << "mount " << part1 << " /mnt/roohaniye-target/boot/efi\n";
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
