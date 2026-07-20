#include "appcenter.h"

#include <QNetworkRequest>
#include <QNetworkReply>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QCryptographicHash>
#include <QFile>
#include <QDir>
#include <QStandardPaths>
#include <QProcess>
#include <QEventLoop>
#include <QSysInfo>

AppCenter::AppCenter(QObject *parent)
    : QObject(parent)
    , m_installedRegistry(QStringLiteral("/opt/roohaniye/data/appcenter_installed.ini"), QSettings::IniFormat)
{
}

QString AppCenter::currentArch() const
{
    const QString a = QSysInfo::currentCpuArchitecture(); // "x86_64", "arm64" etc
    return a;
}

void AppCenter::setBusy(bool b)
{
    if (m_busy == b) return;
    m_busy = b;
    emit busyChanged();
}

void AppCenter::setStatus(const QString &s)
{
    m_statusMessage = s;
    emit statusChanged();
}

void AppCenter::refreshManifest()
{
    setBusy(true);
    setStatus("Fetching app list…");

    QNetworkRequest req{QUrl(kManifestUrl)};
    QNetworkReply *reply = m_net.get(req);

    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            const int httpStatus = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
            if (httpStatus == 404) {
                setStatus("App list isn't published yet. Nothing to install.");
            } else if (reply->error() == QNetworkReply::HostNotFoundError ||
                       reply->error() == QNetworkReply::TimeoutError ||
                       reply->error() == QNetworkReply::UnknownNetworkError) {
                setStatus("Couldn't reach the app center. Check your connection.");
            } else {
                setStatus("App center error: " + reply->errorString());
            }
            setBusy(false);
            return;
        }

        const QJsonDocument doc = QJsonDocument::fromJson(reply->readAll());
        if (!doc.isObject()) {
            setStatus("App list looked corrupted. Try again later.");
            setBusy(false);
            return;
        }
        const QJsonObject root = doc.object();
        const int manifestVersion = root.value("manifest_version").toInt(1);
        if (manifestVersion > kManifestVersionSupported) {
            setStatus("This OS needs an update before it can read the app list.");
            setBusy(false);
            return;
        }

        QVariantList list;
        const QJsonArray arr = root.value("apps").toArray();
        for (const QJsonValue &v : arr) {
            const QJsonObject o = v.toObject();
            QVariantMap m;
            m["id"] = o.value("id").toString();
            m["name"] = o.value("name").toString();
            m["description"] = o.value("description").toString();
            m["license"] = o.value("license").toString();
            m["version"] = o.value("version").toString();
            // Optional fields for the GNOME-Software-style grid. Not yet
            // present in the real manifest (only the VLC test entry
            // exists there) - default gracefully so the UI never shows
            // "undefined". "category" drives the sidebar filter;
            // unrecognized/missing category falls back to "Explore" only
            // (i.e. it just won't appear under a specific category tab).
            m["category"] = o.value("category").toString("Uncategorized");
            m["publisher"] = o.value("publisher").toString();
            m["iconUrl"] = o.value("icon_url").toString();
            list.append(m);
        }
        m_apps = list;
        emit appsChanged();
        setStatus(QString("%1 apps available").arg(list.size()));
        setBusy(false);
    });
}

bool AppCenter::verifySha256(const QString &filePath, const QString &expectedHex) const
{
    QFile f(filePath);
    if (!f.open(QIODevice::ReadOnly)) return false;
    QCryptographicHash hash(QCryptographicHash::Sha256);
    if (!hash.addData(&f)) return false;
    const QString actual = hash.result().toHex();
    return actual.compare(expectedHex, Qt::CaseInsensitive) == 0;
}

bool AppCenter::installDeb(const QString &filePath, QString *errorOut) const
{
    // NOTE: was "pkexec" - changed because pkexec needs a graphical
    // polkit auth agent, which doesn't exist in this kiosk session (see
    // continue.md, "Installer freeze/hang bug"). Same failure mode here:
    // pkexec could hang for the full 120s timeout on every install
    // instead of failing fast. `-n` (non-interactive) makes sudo fail
    // immediately instead of hanging if NOPASSWD isn't set up.
    QProcess proc;
    proc.start("sudo", {"-n", "dpkg", "-i", filePath});
    proc.waitForFinished(120000);
    if (proc.exitCode() != 0) {
        if (errorOut) *errorOut = QString::fromUtf8(proc.readAllStandardError());
        return false;
    }
    return true;
}

bool AppCenter::removeDeb(const QString &packageId, QString *errorOut) const
{
    // NOTE: was "pkexec" - same reasoning as installDeb() above.
    QProcess proc;
    proc.start("sudo", {"-n", "dpkg", "-r", packageId});
    proc.waitForFinished(60000);
    if (proc.exitCode() != 0) {
        if (errorOut) *errorOut = QString::fromUtf8(proc.readAllStandardError());
        return false;
    }
    return true;
}

void AppCenter::recordInstalled(const QString &id, const QString &name,
                                 const QString &version, const QString &license)
{
    m_installedRegistry.beginGroup("app_" + id);
    m_installedRegistry.setValue("id", id);
    m_installedRegistry.setValue("name", name);
    m_installedRegistry.setValue("version", version);
    m_installedRegistry.setValue("license", license);
    m_installedRegistry.endGroup();
    m_installedRegistry.sync();
    emit installedAppsChanged();
}

void AppCenter::forgetInstalled(const QString &id)
{
    m_installedRegistry.remove("app_" + id);
    m_installedRegistry.sync();
    emit installedAppsChanged();
}

QVariantList AppCenter::installedApps() const
{
    QVariantList out;
    for (const QString &group : m_installedRegistry.childGroups()) {
        if (!group.startsWith("app_")) continue;
        m_installedRegistry.beginGroup(group);
        QVariantMap m;
        m["id"] = m_installedRegistry.value("id").toString();
        m["name"] = m_installedRegistry.value("name").toString();
        m["version"] = m_installedRegistry.value("version").toString();
        m["license"] = m_installedRegistry.value("license").toString();
        m_installedRegistry.endGroup();
        out.append(m);
    }
    return out;
}

bool AppCenter::isInstalled(const QString &id) const
{
    return m_installedRegistry.childGroups().contains("app_" + id);
}

QVariantList AppCenter::availableUpdates() const
{
    QVariantList out;
    for (const QVariant &installedVar : installedApps()) {
        const QVariantMap installed = installedVar.toMap();
        for (const QVariant &manifestVar : m_apps) {
            const QVariantMap manifestApp = manifestVar.toMap();
            if (manifestApp["id"] == installed["id"] &&
                manifestApp["version"] != installed["version"]) {
                QVariantMap m;
                m["id"] = installed["id"];
                m["name"] = installed["name"];
                m["installedVersion"] = installed["version"];
                m["availableVersion"] = manifestApp["version"];
                out.append(m);
            }
        }
    }
    return out;
}

void AppCenter::uninstallApp(const QString &id)
{
    setBusy(true);
    setStatus(QString("Removing %1…").arg(id));

    QString err;
    // See the header comment on uninstallApp: assumes manifest id ==
    // dpkg package name.
    const bool ok = removeDeb(id, &err);
    setBusy(false);
    if (ok) {
        forgetInstalled(id);
        setStatus(QString("%1 removed").arg(id));
        emit uninstallFinished(id, true, "");
    } else {
        setStatus("Remove failed: " + err);
        emit uninstallFinished(id, false, err);
    }
}

void AppCenter::installApp(const QString &id)
{
    setBusy(true);
    setStatus(QString("Preparing to install %1…").arg(id));

    // Re-fetch manifest to get full per-app arch/url/sha256 (kept out of the
    // slim list used for the grid to keep that payload small).
    QNetworkRequest req{QUrl(kManifestUrl)};
    QNetworkReply *reply = m_net.get(req);

    connect(reply, &QNetworkReply::finished, this, [this, reply, id]() {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            setStatus("Couldn't reach the app center.");
            setBusy(false);
            emit installFinished(id, false, "Network error");
            return;
        }

        const QJsonObject root = QJsonDocument::fromJson(reply->readAll()).object();
        QJsonObject target;
        for (const QJsonValue &v : root.value("apps").toArray()) {
            if (v.toObject().value("id").toString() == id) { target = v.toObject(); break; }
        }
        if (target.isEmpty()) {
            setStatus("App not found in the list anymore.");
            setBusy(false);
            emit installFinished(id, false, "Not found");
            return;
        }

        const QJsonObject archObj = target.value("arch").toObject().value(currentArch()).toObject();
        if (archObj.isEmpty()) {
            setStatus("Not available for this device's processor.");
            setBusy(false);
            emit installFinished(id, false, "No build for this arch");
            return;
        }

        const QString downloadUrl = archObj.value("url").toString();
        const QString expectedSha = archObj.value("sha256").toString();
        const QString type = archObj.value("type").toString();

        if (downloadUrl.isEmpty() || expectedSha.isEmpty()) {
            setStatus("Listing is missing required info. Refusing to install.");
            setBusy(false);
            emit installFinished(id, false, "Missing url/sha256");
            return;
        }

        setStatus(QString("Downloading %1…").arg(id));
        QNetworkRequest dlReq{QUrl(downloadUrl)};
        QNetworkReply *dlReply = m_net.get(dlReq);

        const QString appName = target.value("name").toString();
        const QString appVersion = target.value("version").toString();
        const QString appLicense = target.value("license").toString();

        connect(dlReply, &QNetworkReply::finished, this,
                [this, dlReply, id, expectedSha, type, appName, appVersion, appLicense]() {
            dlReply->deleteLater();
            if (dlReply->error() != QNetworkReply::NoError) {
                setStatus("Download failed.");
                setBusy(false);
                emit installFinished(id, false, "Download error");
                return;
            }

            const QString cacheDir = QStandardPaths::writableLocation(QStandardPaths::CacheLocation);
            QDir().mkpath(cacheDir);
            const QString outPath = cacheDir + "/" + id + "." + type;

            QFile out(outPath);
            if (!out.open(QIODevice::WriteOnly)) {
                setStatus("Couldn't write to disk.");
                setBusy(false);
                emit installFinished(id, false, "Write error");
                return;
            }
            out.write(dlReply->readAll());
            out.close();

            setStatus("Verifying download…");
            if (!verifySha256(outPath, expectedSha)) {
                QFile::remove(outPath);
                setStatus("Checksum didn't match. Install blocked for safety.");
                setBusy(false);
                emit installFinished(id, false, "Checksum mismatch");
                return;
            }

            setStatus(QString("Installing %1…").arg(id));
            QString err;
            bool ok = false;
            if (type == "deb") {
                ok = installDeb(outPath, &err);
            } else {
                err = "Unsupported package type: " + type;
            }

            QFile::remove(outPath);
            setBusy(false);
            if (ok) {
                setStatus(QString("%1 installed").arg(id));
                recordInstalled(id, appName, appVersion, appLicense);
                emit installFinished(id, true, "");
            } else {
                setStatus("Install failed: " + err);
                emit installFinished(id, false, err);
            }
        });
    });
}
