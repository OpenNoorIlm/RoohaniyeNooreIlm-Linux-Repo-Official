// InstallerBackend: the missing piece flagged by the user - after
// booting a "Try RoohaniyeNooreIlm" live USB, there was no actual way to
// install it permanently to the machine's own disk. This backend is the
// real "Install RoohaniyeNooreIlm" app: pick a target disk, optionally
// pull in fuller replacement databases from a USB stick (e.g. a real
// quran_audio.db instead of whatever shipped on the live image),
// confirm, and it partitions/formats/copies/installs a bootloader for
// real.
//
// SCOPE NOTE (read this before touching the install pipeline): this
// project has no separate live-build/debootstrap/squashfs pipeline
// anywhere in this repo - "the OS" is just this Qt shell running on top
// of whatever base Linux the live USB happens to be. So "installing the
// OS" here pragmatically means: partition + format the target disk,
// rsync the CURRENTLY RUNNING filesystem onto it (the live session IS
// the source image, same trick many lightweight live-USB installers
// use), copy over /opt/roohaniye/data (with any user-picked
// replacements), install GRUB, and drop in a systemd unit + autologin
// so the target disk boots straight into roohaniye-shell fullscreen. If
// a real ISO/live-build pipeline gets built later, only step 4
// (cloneRunningSystem) in installerbackend.cpp needs to change to
// extract a squashfs instead.
//
// SAFETY - READ BEFORE CALLING startInstall():
//   - listDisks() EXCLUDES whatever disk currently backs "/" (resolved
//     via findmnt), so the running system's own disk is never even
//     selectable, live-boot or dev-box alike.
//   - startInstall() re-validates the confirm text server-side
//     ("ERASE", case-sensitive) even though the QML wizard already
//     gates its own "Install now" button on it - never trust the UI
//     layer alone for something this destructive.
//   - The actual partition/format/copy/grub work runs as a single
//     generated shell script executed via `pkexec sh <script>`, not
//     scattered pkexec calls - one polkit prompt, one place to read the
//     exact commands that will run, one log.
//   - THIS PIPELINE HAS NOT BEEN EXECUTED AGAINST REAL HARDWARE in the
//     session that wrote it (deliberately - it was developed and code-
//     reviewed on the same machine it would have to wipe to test for
//     real). listDisks()/isInstalled()/directory listing (all
//     read-only) were exercised headlessly; startInstall()'s actual
//     script was reviewed but not run. Test on a spare disk or a VM
//     before trusting this on real hardware.
#pragma once

#include <QObject>
#include <QVariantList>
#include <QVariantMap>
#include <QProcess>

class InstallerBackend : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool installRunning READ installRunning NOTIFY installRunningChanged)

public:
    explicit InstallerBackend(QObject *parent = nullptr);

    bool installRunning() const { return m_installRunning; }

    // True once a previous run of startInstall() completed successfully
    // on THIS disk (marker file at kMarkerPath). Drives whether the
    // "Install RoohaniyeNooreIlm" tile/banner shows at all - once true,
    // it's gone for good (not per-boot, not dismissible-and-back) unless
    // the marker file is manually removed.
    Q_INVOKABLE bool isInstalled() const;

    // Real, read-only disk enumeration via `lsblk -J` (full tree,
    // including partitions, so we can warn before anything is erased).
    // Each entry: { path, name, sizeLabel, sizeBytes, model, transport
    // ("usb"/"sata"/"nvme"/...), isRemovable, partitionTableType
    // ("gpt"/"dos"/"none"), partitionCount, isBlank (no partition table
    // and no partitions), hasEncryption (LUKS or BitLocker found on any
    // partition), warnings (QStringList-as-QVariantList of human-
    // readable strings - existing partitions, encryption, detected
    // Windows/Linux installs - meant to be shown prominently in the
    // disk picker and again at the final review step before ERASE).
    // Detection here is all unprivileged (lsblk only, no os-prober/
    // mounting) so it stays fast enough to call on every UI refresh;
    // it can say "an NTFS/ext4 partition exists" but not confidently
    // identify which OS/version is on it. Always excludes the disk
    // backing the currently-running root filesystem - see class
    // comment. Returns [] (with lsblk missing/failing) rather than ever
    // guessing.
    Q_INVOKABLE QVariantList listDisks() const;

    // Lightweight browser for picking replacement/extra database files
    // off removable storage during setup - same shape as
    // DbConnectorBackend::listDirectory (name, path, isDir, isDb,
    // isJson, sizeLabel) so the QML delegate code is interchangeable.
    // Deliberately NOT sharing DbConnectorBackend directly: that class
    // is wired to QuranBackend's live hot-swap, whereas here we're just
    // staging file paths to be copied onto a not-yet-booted target disk.
    Q_INVOKABLE QVariantList listDirectory(const QString &path) const;

    // Kicks off the real install pipeline on a background thread (so
    // the QML progress/animation screen keeps rendering). `options`:
    //   diskPath        - e.g. "/dev/sdb", must be one of listDisks()'s
    //                     entries (re-checked here, not just trusted).
    //   confirmText     - must be exactly "ERASE" or this call refuses
    //                     outright and emits installFinished(false, ...)
    //                     synchronously without touching anything.
    //   extraDatabases  - [ { sourcePath, targetFile } ], targetFile
    //                     one of "quran_text.db"/"quran_audio.db"/
    //                     "hadiths.db" - copied in AFTER the base clone,
    //                     overwriting whatever the live system shipped
    //                     with under that name.
    //   account         - OPTIONAL { username, password, isAdmin }. If
    //                     present, a fresh accounts.dat (same PBKDF2
    //                     format AuthBackend uses) is generated
    //                     standalone - via AuthBackend::exportAccountForInstall,
    //                     which never touches THIS live session's own
    //                     accounts - and copied onto the target disk, so
    //                     the freshly-installed system boots straight to
    //                     a login screen instead of an unlocked shell.
    //                     Omit entirely to leave the target unlocked
    //                     (Settings can always set an account up later).
    // Progress/result arrive via the signals below, not a return value.
    Q_INVOKABLE void startInstall(const QVariantMap &options);

    // Best-effort cancel: kills the running helper script if any step
    // hasn't already committed past the point of no return (partitioning
    // has started). Emits installFinished(false, "Cancelled by user")
    // if it managed to stop in time.
    Q_INVOKABLE void cancelInstall();

    // Reboots the machine right now via `systemctl reboot` (falls back
    // to `pkexec reboot` if systemctl isn't reachable without a prompt).
    // Only meant to be called from the post-install success screen,
    // after the user has confirmed they've removed the install USB -
    // this file never checks that itself, it just reboots on request.
    Q_INVOKABLE void rebootSystem() const;

signals:
    void installRunningChanged();
    // stage: short machine-friendly key ("partitioning", "formatting",
    // "cloning", "databases", "bootloader", "finishing") for the QML
    // side to map to its own copy/icon/animation per stage.
    void installProgress(int percent, const QString &stage, const QString &detail);
    void installLog(const QString &line);
    void installFinished(bool ok, const QString &error);
    // Fired once, synchronously, right at the start of startInstall()
    // if an `account` option was given and export succeeded - BEFORE
    // the (slow, destructive) script even runs. The QML wizard should
    // hold onto this and only actually show it to the user once
    // installFinished(true, ...) confirms the disk write succeeded.
    void installAccountRecoveryCode(const QString &username, const QString &code);

private:
    QString findRootDisk() const; // disk device backing "/", to exclude from listDisks()
    QString buildInstallScript(const QVariantMap &options, QString &error) const;

    bool m_installRunning = false;
    QProcess *m_proc = nullptr;
};
