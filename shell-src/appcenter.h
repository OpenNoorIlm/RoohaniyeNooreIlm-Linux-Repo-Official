// AppCenter: fetches apps.json from the official GitHub repo, verifies
// checksums, and installs. This is the ONLY sanctioned way to add software
// to the OS. No apt, no arbitrary curl exposed to the user.
#pragma once

#include <QObject>
#include <QVariantList>
#include <QString>
#include <QNetworkAccessManager>
#include <QSettings>

class AppCenter : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantList apps READ apps NOTIFY appsChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(QString statusMessage READ statusMessage NOTIFY statusChanged)

public:
    explicit AppCenter(QObject *parent = nullptr);

    QVariantList apps() const { return m_apps; }
    bool busy() const { return m_busy; }
    QString statusMessage() const { return m_statusMessage; }

    // Called from QML on App Center open / pull-to-refresh
    Q_INVOKABLE void refreshManifest();

    // id = the "id" field from apps.json
    Q_INVOKABLE void installApp(const QString &id);

    // ---- Manage tab: local install registry ----
    // NOTE: uninstall assumes the manifest "id" matches the installed
    // dpkg package name (true for the current test entry, "vlc" -> the
    // vlc package). If a future manifest entry's package name differs
    // from its id, this needs a stored packageName field alongside id -
    // not modeled yet since only one real entry exists so far.
    Q_INVOKABLE QVariantList installedApps() const; // [{id, name, version, license}]
    Q_INVOKABLE bool isInstalled(const QString &id) const;
    Q_INVOKABLE void uninstallApp(const QString &id);

    // Cross-references installedApps() against the current manifest by id:
    // any installed app whose manifest "version" differs from the
    // installed-at-time version we recorded is reported as updatable.
    // This is a manifest-version diff, not a real dpkg/apt "is a newer
    // .deb available" check - good enough since every install goes
    // through this app center anyway (nothing else can change a
    // package's version on this OS), but call refreshManifest() first if
    // you want this to reflect the latest listing.
    Q_INVOKABLE QVariantList availableUpdates() const;

signals:
    void appsChanged();
    void busyChanged();
    void statusChanged();
    void installFinished(const QString &id, bool success, const QString &message);
    void uninstallFinished(const QString &id, bool success, const QString &message);
    void installedAppsChanged();

private:
    static constexpr const char *kManifestUrl =
        "https://raw.githubusercontent.com/OpenNoorIlm/"
        "RoohaniyeNooreIlmLinux-App-Center/main/apps.json";
    static constexpr int kManifestVersionSupported = 1;

    void setBusy(bool b);
    void setStatus(const QString &s);
    bool verifySha256(const QString &filePath, const QString &expectedHex) const;
    bool installDeb(const QString &filePath, QString *errorOut) const;
    bool removeDeb(const QString &packageId, QString *errorOut) const;
    QString currentArch() const; // "x86_64" or "arm64"
    void recordInstalled(const QString &id, const QString &name,
                          const QString &version, const QString &license);
    void forgetInstalled(const QString &id);

    QNetworkAccessManager m_net;
    QVariantList m_apps;
    bool m_busy = false;
    QString m_statusMessage;
    mutable QSettings m_installedRegistry;
};
