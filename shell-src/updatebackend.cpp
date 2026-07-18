#include "updatebackend.h"

#include <QNetworkRequest>
#include <QNetworkReply>
#include <QJsonDocument>
#include <QJsonObject>
#include <QCryptographicHash>
#include <QFile>
#include <QDir>
#include <QSysInfo>
#include <QVersionNumber>
#include <QTimer>
#include <QTextStream>

UpdateBackend::UpdateBackend(QObject *parent)
    : QObject(parent)
{
}

QString UpdateBackend::currentVersion() const
{
    QFile f("/opt/roohaniye/VERSION");
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text)) return "0.0.0";
    const QString v = QString::fromUtf8(f.readAll()).trimmed();
    return v.isEmpty() ? "0.0.0" : v;
}

QString UpdateBackend::currentArch() const
{
    return QSysInfo::currentCpuArchitecture(); // "x86_64", "arm64" etc
}

void UpdateBackend::setBusy(bool b)
{
    if (m_busy == b) return;
    m_busy = b;
    emit busyChanged();
}

void UpdateBackend::setStatus(const QString &s)
{
    m_statusMessage = s;
    emit statusChanged();
}

bool UpdateBackend::verifySha256(const QString &filePath, const QString &expectedHex) const
{
    QFile f(filePath);
    if (!f.open(QIODevice::ReadOnly)) return false;
    QCryptographicHash hash(QCryptographicHash::Sha256);
    if (!hash.addData(&f)) return false;
    return hash.result().toHex().compare(expectedHex.toUtf8(), Qt::CaseInsensitive) == 0;
}

void UpdateBackend::checkForUpdate()
{
    setBusy(true);
    setStatus("Checking for updates…");

    QNetworkRequest req{QUrl(kManifestUrl)};
    QNetworkReply *reply = m_net.get(req);

    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            const int httpStatus = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
            if (httpStatus == 404) {
                setStatus("No update manifest has been published yet.");
            } else if (reply->error() == QNetworkReply::HostNotFoundError ||
                       reply->error() == QNetworkReply::TimeoutError ||
                       reply->error() == QNetworkReply::UnknownNetworkError) {
                setStatus("Couldn't reach the update server. Check your connection.");
            } else {
                setStatus("Update check error: " + reply->errorString());
            }
            setBusy(false);
            emit checkFinished(false, QString(), QString());
            return;
        }

        const QJsonDocument doc = QJsonDocument::fromJson(reply->readAll());
        if (!doc.isObject()) {
            setStatus("Update manifest looked corrupted.");
            setBusy(false);
            emit checkFinished(false, QString(), QString());
            return;
        }

        const QJsonObject root = doc.object();
        const int manifestVersion = root.value("manifest_version").toInt(1);
        if (manifestVersion > kManifestVersionSupported) {
            setStatus("An update is available, but this OS is too old to read its manifest. Manual intervention needed.");
            setBusy(false);
            emit checkFinished(false, QString(), QString());
            return;
        }

        const QString latest = root.value("latest_version").toString();
        const QString notes = root.value("release_notes").toString();
        const QJsonObject archObj = root.value("arch").toObject().value(currentArch()).toObject();

        if (latest.isEmpty() || archObj.isEmpty()) {
            setStatus("No build listed for this device yet.");
            setBusy(false);
            emit checkFinished(false, QString(), QString());
            return;
        }

        m_pendingDownloadUrl = archObj.value("url").toString();
        m_pendingSha256 = archObj.value("sha256").toString();
        m_pendingType = archObj.value("type").toString();
        m_pendingVersion = latest;

        const QVersionNumber cur = QVersionNumber::fromString(currentVersion());
        const QVersionNumber lat = QVersionNumber::fromString(latest);
        const bool available = QVersionNumber::compare(lat, cur) > 0;

        setStatus(available ? QString("Update available: %1").arg(latest)
                             : "You're on the latest version.");
        setBusy(false);
        emit checkFinished(available, latest, notes);
    });
}

void UpdateBackend::downloadUpdate()
{
    if (m_pendingDownloadUrl.isEmpty() || m_pendingSha256.isEmpty()) {
        setStatus("Run a check for updates first.");
        emit downloadFinished(false, QString(), "No pending update to download");
        return;
    }

    setBusy(true);
    setStatus(QString("Downloading update %1…").arg(m_pendingVersion));

    QNetworkRequest req{QUrl(m_pendingDownloadUrl)};
    QNetworkReply *reply = m_net.get(req);

    connect(reply, &QNetworkReply::downloadProgress, this, &UpdateBackend::downloadProgress);

    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            setStatus("Download failed.");
            setBusy(false);
            emit downloadFinished(false, QString(), "Download error: " + reply->errorString());
            return;
        }

        const QString outDir = "/opt/roohaniye/updates";
        QDir().mkpath(outDir);
        const QString outPath = outDir + "/" + m_pendingVersion + "." + m_pendingType;

        QFile out(outPath);
        if (!out.open(QIODevice::WriteOnly)) {
            setStatus("Couldn't write the update to disk.");
            setBusy(false);
            emit downloadFinished(false, QString(), "Write error");
            return;
        }
        out.write(reply->readAll());
        out.close();

        setStatus("Verifying download…");
        if (!verifySha256(outPath, m_pendingSha256)) {
            QFile::remove(outPath);
            setStatus("Checksum didn't match. Update blocked for safety.");
            setBusy(false);
            emit downloadFinished(false, QString(), "Checksum mismatch");
            return;
        }

        setStatus(QString("Update %1 downloaded and verified").arg(m_pendingVersion));
        setBusy(false);
        emit downloadFinished(true, outPath, "");
    });
}

QString UpdateBackend::applyInstructions() const
{
    return "This update has been downloaded and checksum-verified. It "
           "will install itself and reboot automatically within a "
           "moment - no further action needed.";
}

void UpdateBackend::startAutoUpdateCycle(int intervalHours)
{
    if (m_autoCycleStarted) return;
    m_autoCycleStarted = true;

    // Chain check -> download -> apply with no user interaction. These
    // connections stay live for the whole process lifetime, so a manual
    // "Check for updates" tap from the UI chains through automatically
    // too - there's deliberately only one path through this class now,
    // not a separate "peek without installing" mode.
    connect(this, &UpdateBackend::checkFinished, this,
            [this](bool available, const QString &, const QString &) {
                if (available && !m_busy) downloadUpdate();
            });
    connect(this, &UpdateBackend::downloadFinished, this,
            [this](bool success, const QString &, const QString &) {
                if (success) applyUpdate();
            });

    // First check shortly after startup rather than instantly, so it
    // doesn't compete with the app's own boot-time DB-opening work.
    QTimer::singleShot(2 * 60 * 1000, this, &UpdateBackend::checkForUpdate);

    auto *timer = new QTimer(this);
    timer->setInterval(qMax(1, intervalHours) * 3600 * 1000);
    connect(timer, &QTimer::timeout, this, &UpdateBackend::checkForUpdate);
    timer->start();
}

void UpdateBackend::applyUpdate()
{
    if (m_pendingVersion.isEmpty() || m_pendingType.isEmpty()) {
        setStatus("No downloaded update staged to apply.");
        return;
    }

    // Matches the exact path downloadUpdate() wrote to and verified.
    const QString pkgPath = QString("/opt/roohaniye/updates/%1.%2")
                                 .arg(m_pendingVersion, m_pendingType);
    if (!QFile::exists(pkgPath)) {
        setStatus("Staged update file is missing.");
        return;
    }

    const QString markerPath = "/opt/roohaniye/updates/pending.marker";
    QFile marker(markerPath);
    if (!marker.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text)) {
        setStatus("Couldn't stage the update for install.");
        return;
    }
    {
        QTextStream ts(&marker);
        ts << m_pendingVersion << "\n" << pkgPath << "\n";
    }
    marker.close();

    setStatus(QString("Update %1 verified - installing and rebooting shortly…").arg(m_pendingVersion));
    emit updateStaged(m_pendingVersion);
    // roohaniye-updater.path (root, systemd) takes it from here: fires
    // roohaniye-updater.service -> apply-update.sh, which stops this
    // app, extracts the archive over /, runs postinst.sh if present,
    // and reboots. See updatebackend.h for why this isn't done via
    // pkexec from this unprivileged process.
}
