#include "wifibackend.h"
#include <QStringList>
#include <QSet>

WifiBackend::WifiBackend(QObject *parent) : QObject(parent)
{
    refreshWifiState();
}

void WifiBackend::setScanning(bool b)
{
    if (m_scanning == b) return;
    m_scanning = b;
    emit scanningChanged();
}

void WifiBackend::setStatus(const QString &s)
{
    m_statusMessage = s;
    emit statusChanged();
}

void WifiBackend::refreshWifiState()
{
    QProcess proc;
    proc.start("nmcli", {"radio", "wifi"});
    proc.waitForFinished(3000);
    const QString out = QString::fromUtf8(proc.readAllStandardOutput()).trimmed();
    const bool enabled = out.compare("enabled", Qt::CaseInsensitive) == 0;
    if (enabled != m_wifiEnabled) {
        m_wifiEnabled = enabled;
        emit wifiEnabledChanged();
    }
}

void WifiBackend::setWifiEnabled(bool enabled)
{
    QProcess *proc = new QProcess(this);
    connect(proc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, [this, proc, enabled](int, QProcess::ExitStatus) {
        proc->deleteLater();
        m_wifiEnabled = enabled;
        emit wifiEnabledChanged();
        if (enabled) scan();
    });
    proc->start("nmcli", {"radio", "wifi", enabled ? "on" : "off"});
}

void WifiBackend::scan()
{
    if (m_scanning) return; // avoid overlapping nmcli calls stacking up
    setScanning(true);
    setStatus("Scanning for networks…");

    QProcess *proc = new QProcess(this);
    connect(proc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, [this, proc](int exitCode, QProcess::ExitStatus) {
        proc->deleteLater();
        setScanning(false);

        if (exitCode != 0) {
            setStatus("Couldn't scan for networks. Is WiFi hardware available?");
            return;
        }

        const QString out = QString::fromUtf8(proc->readAllStandardOutput());
        const QStringList lines = out.split('\n', Qt::SkipEmptyParts);

        QVariantList list;
        QSet<QString> seenSsids;
        for (const QString &line : lines) {
            // Format from `nmcli -t -f SSID,SIGNAL,SECURITY dev wifi list`:
            // SSID:SIGNAL:SECURITY  (colon separated, escaped colons unlikely in practice here)
            const QStringList parts = line.split(':');
            if (parts.size() < 3) continue;
            const QString ssid = parts.at(0);
            if (ssid.isEmpty() || seenSsids.contains(ssid)) continue;
            seenSsids.insert(ssid);

            QVariantMap m;
            m["ssid"] = ssid;
            m["signal"] = parts.at(1).toInt();
            m["secured"] = !parts.at(2).isEmpty();
            list.append(m);
        }

        // Strongest signal first.
        std::sort(list.begin(), list.end(), [](const QVariant &a, const QVariant &b) {
            return a.toMap()["signal"].toInt() > b.toMap()["signal"].toInt();
        });

        m_networks = list;
        emit networksChanged();
        setStatus(QString("%1 networks found").arg(list.size()));
    });

    // --rescan yes forces NetworkManager to do a fresh scan instead of
    // returning whatever it last cached, which is what was causing stale/
    // empty results until a second visit to the screen.
    proc->start("nmcli", {"-t", "-f", "SSID,SIGNAL,SECURITY", "dev", "wifi", "list", "--rescan", "yes"});
}

void WifiBackend::connectToNetwork(const QString &ssid, const QString &password)
{
    setStatus(QString("Connecting to %1…").arg(ssid));

    QProcess *proc = new QProcess(this);
    connect(proc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, [this, proc, ssid](int exitCode, QProcess::ExitStatus) {
        proc->deleteLater();
        const QString err = QString::fromUtf8(proc->readAllStandardError());
        if (exitCode == 0) {
            setStatus(QString("Connected to %1").arg(ssid));
            emit connectFinished(true, "");
        } else {
            setStatus("Couldn't connect: " + err);
            emit connectFinished(false, err);
        }
    });

    QStringList args = {"dev", "wifi", "connect", ssid};
    if (!password.isEmpty()) {
        args << "password" << password;
    }
    proc->start("nmcli", args);
}
