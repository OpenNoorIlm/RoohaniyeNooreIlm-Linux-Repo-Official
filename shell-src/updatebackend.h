// UpdateBackend: checks the official distro-download repo
// (OpenNoorIlm/RoohaniyeNooreIlm-Linux-Repo-Official) for a newer OS
// image, and downloads+sha256-verifies it if the user chooses to. This is
// the ONLY sanctioned source for OS updates - same "curated, checksum-
// verified, no arbitrary downloads" philosophy as AppCenter, just for the
// OS image itself instead of individual apps.
//
// IMPORTANT SCOPE NOTE: this class checks for and downloads an update
// image; it does NOT apply/flash it. Actually writing a new OS image over
// the running system is destructive and highly hardware/partition-layout
// specific (different on an x86 laptop vs a Raspberry-Pi-class ARM
// board), so that step is deliberately left as a manual, explicit action
// for the user to perform (or a future, carefully-designed separate
// tool) rather than something this class does silently. See
// `applyInstructions()`.
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

    // A human-readable string describing that applying an OS update is a
    // manual step (this class deliberately does not flash/apply images -
    // see class comment), for the UI to display once a download
    // succeeds.
    Q_INVOKABLE QString applyInstructions() const;

signals:
    void busyChanged();
    void statusChanged();
    // available: whether latestVersion != currentVersion(). notes: the
    // manifest's release_notes field (empty if none).
    void checkFinished(bool available, const QString &latestVersion, const QString &notes);
    void downloadProgress(qint64 bytesReceived, qint64 bytesTotal);
    void downloadFinished(bool success, const QString &filePath, const QString &message);

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

    // Cached from the last successful checkForUpdate(), so
    // downloadUpdate() doesn't need to re-fetch/re-parse the manifest.
    QString m_pendingDownloadUrl;
    QString m_pendingSha256;
    QString m_pendingType;
    QString m_pendingVersion;
};
