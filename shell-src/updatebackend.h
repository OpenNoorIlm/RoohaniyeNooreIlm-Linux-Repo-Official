// UpdateBackend: checks the official distro-download repo
// (OpenNoorIlm/RoohaniyeNooreIlm-Linux-Repo-Official) for a newer OS
// image, downloads+sha256-verifies it, and stages it for install - all
// fully automatically, no user tap required (see startAutoUpdateCycle()).
// This is the ONLY sanctioned source for OS updates - same "curated,
// checksum-verified, no arbitrary downloads" philosophy as AppCenter,
// just for the OS image itself instead of individual apps.
//
// SCOPE / PRIVILEGE SPLIT - READ BEFORE TOUCHING THIS CLASS:
// This process runs unprivileged as `ubuntu` (see roohaniye-kiosk.service).
// It deliberately does NOT try to apply the update itself via pkexec:
// pkexec needs an interactive graphical polkit agent to click "Authenticate",
// and this eglfs kiosk session has no desktop environment / polkit agent
// running at all - a pkexec call here would just hang or fail with no
// one able to approve it. Instead:
//   1. This class (unprivileged) checks, downloads, and sha256-verifies
//      into /opt/roohaniye/updates/ (pre-created ubuntu-owned in the
//      image - see live-build notes), then calls applyUpdate(), which
//      just writes a small plaintext marker file there.
//   2. A root-owned systemd path unit (roohaniye-updater.path) watches
//      for that marker file with no polkit/human involved - systemd
//      units aren't gated by interactive auth, they just run as
//      whatever User= they're configured for (root, here).
//   3. When the marker appears, roohaniye-updater.service fires
//      /opt/roohaniye/bin/apply-update.sh as root, which stops the
//      kiosk service, extracts the verified archive over /, runs an
//      optional postinst.sh from the package (for OS-level tweaks like
//      systemd unit/group changes - the same kind of fix this session
//      made to the live-build chroot directly), and reboots.
//
// ACCEPTED TRADEOFF (explicit user decision, not an oversight): there is
// NO A/B partition and NO pre-apply snapshot/rollback here. If power is
// lost mid-`cp -a` in apply-update.sh, the device can be left unable to
// boot. A safer dual-slot or snapshot+rollback design was offered and
// declined in favor of getting fully-automatic updates shipped now.
#pragma once

#include <QObject>
#include <QString>
#include <QNetworkAccessManager>

class UpdateBackend : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString currentVersion READ currentVersion CONSTANT)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(QString statusMessage READ statusMessage NOTIFY statusChanged)

public:
    explicit UpdateBackend(QObject *parent = nullptr);

    // Reads /opt/roohaniye/VERSION (plain text, e.g. "0.1.0"). Returns
    // "0.0.0" if the file doesn't exist yet (fresh/dev installs).
    QString currentVersion() const;
    bool busy() const { return m_busy; }
    QString statusMessage() const { return m_statusMessage; }

    // Fetches manifest.json from the distro repo and compares
    // latest_version against currentVersion(). Emits checkFinished()
    // either way (available=false also covers "already up to date" and
    // "manifest not published yet" - check statusMessage for which).
    Q_INVOKABLE void checkForUpdate();

    // Downloads the update image for this device's architecture and
    // verifies its sha256 against the manifest. Call only after
    // checkForUpdate() reported one available. On success the verified
    // file is left at /opt/roohaniye/updates/<version>.<type> and
    // downloadFinished(true, path, "") is emitted; the file is deleted
    // and downloadFinished(false, "", error) is emitted on any failure
    // (network error or checksum mismatch).
    Q_INVOKABLE void downloadUpdate();

    // A human-readable string describing what happens next once a
    // download succeeds (now: automatic background install + reboot,
    // not a manual step - see class comment). Kept for the UI to show.
    Q_INVOKABLE QString applyInstructions() const;

    // Starts the fully-automatic background cycle: checks once shortly
    // after startup, then again every intervalHours, and if a newer
    // version is found, chains straight through download -> verify ->
    // applyUpdate() with no user interaction at any step. Call once from
    // main.cpp right after construction. Safe to call more than once
    // (only the first call does anything).
    Q_INVOKABLE void startAutoUpdateCycle(int intervalHours = 6);

    // Stages an already-downloaded, checksum-verified update (from
    // m_pendingVersion/m_pendingType, set by the last successful
    // downloadUpdate()) for the root-owned updater path/service pair to
    // pick up - see class comment for the full handoff. Safe to call
    // manually too (e.g. a "Restart & install now" button), not just
    // from the auto cycle.
    Q_INVOKABLE void applyUpdate();

signals:
    void busyChanged();
    void statusChanged();
    // available: whether latestVersion != currentVersion(). notes: the
    // manifest's release_notes field (empty if none).
    void checkFinished(bool available, const QString &latestVersion, const QString &notes);
    void downloadProgress(qint64 bytesReceived, qint64 bytesTotal);
    void downloadFinished(bool success, const QString &filePath, const QString &message);
    // Marker written, root-side apply is about to start - the device
    // will reboot on its own within moments of this firing.
    void updateStaged(const QString &version);

private:
    static constexpr const char *kManifestUrl =
        "https://raw.githubusercontent.com/OpenNoorIlm/"
        "RoohaniyeNooreIlm-Linux-Repo-Official/main/manifest.json";
    static constexpr int kManifestVersionSupported = 1;

    void setBusy(bool b);
    void setStatus(const QString &s);
    bool verifySha256(const QString &filePath, const QString &expectedHex) const;
    QString currentArch() const;

    QNetworkAccessManager m_net;
    bool m_busy = false;
    QString m_statusMessage;
    bool m_autoCycleStarted = false;

    // Cached from the last successful checkForUpdate(), so
    // downloadUpdate() doesn't need to re-fetch/re-parse the manifest.
    QString m_pendingDownloadUrl;
    QString m_pendingSha256;
    QString m_pendingType;
    QString m_pendingVersion;
};
