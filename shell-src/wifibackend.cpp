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
            const QString reason = diagnoseWifiIssue();
            setStatus(reason.isEmpty()
                ? "Couldn't scan for networks. Is WiFi hardware available?"
                : reason);
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

QString WifiBackend::diagnoseWifiIssue() const
{
    // 1. Find the wifi device name and NetworkManager's own state/reason
    // for it - this is the single most authoritative source (NM knows
    // exactly why it thinks the device is unusable), so check it first.
    QProcess devProc;
    devProc.start("nmcli", {"-t", "-f", "DEVICE,TYPE,STATE", "device"});
    devProc.waitForFinished(3000);
    const QStringList devLines = QString::fromUtf8(devProc.readAllStandardOutput())
        .split('\n', Qt::SkipEmptyParts);

    QString wifiDevice;
    QString wifiState;
    for (const QString &line : devLines) {
        const QStringList parts = line.split(':');
        if (parts.size() >= 3 && parts.at(1) == "wifi") {
            wifiDevice = parts.at(0);
            wifiState = parts.at(2);
            break;
        }
    }

    if (wifiDevice.isEmpty()) {
        // No wifi-type device at all - either no wifi card, or the kernel
        // driver never bound to it (e.g. missing firmware). rfkill can
        // still tell us if the radio itself is blocked even with no
        // device node, so don't return yet - fall through to the rfkill
        // check below and combine both findings.
        wifiState = "(no wifi device found)";
    }

    // 2. rfkill: distinguishes a HARD block (physical switch/Fn-key/
    // airplane-mode toggle - software cannot clear this, only the user
    // flipping the switch can) from a SOFT block (leftover software
    // block - rfkill-unblock.service should already clear this at boot,
    // so seeing one here means that service didn't run or was undone
    // afterward).
    QProcess rfProc;
    rfProc.start("rfkill", {"list", "wifi"});
    rfProc.waitForFinished(3000);
    const QString rfOut = QString::fromUtf8(rfProc.readAllStandardOutput());
    const bool hardBlocked = rfOut.contains("Hard blocked: yes");
    const bool softBlocked = rfOut.contains("Soft blocked: yes");

    if (hardBlocked) {
        return "WiFi is switched off at the hardware level - check for an "
               "airplane-mode key or physical WiFi switch on this device "
               "and turn it back on. This can't be fixed from software.";
    }
    if (softBlocked) {
        return "WiFi was software-blocked (rfkill) - tap the WiFi toggle "
               "again to clear it.";
    }

    if (wifiDevice.isEmpty()) {
        return "No WiFi hardware was found by the system. If this device "
               "has a WiFi card, its driver or firmware may not be loaded.";
    }

    if (wifiState.contains("unavailable", Qt::CaseInsensitive)) {
        // rfkill says nothing is blocked and the driver did create a
        // device node, so NetworkManager itself is refusing to manage
        // it - ask it directly for the reason rather than guessing.
        QProcess reasonProc;
        reasonProc.start("nmcli", {"-t", "-f", "GENERAL.STATE,GENERAL.REASON", "device", "show", wifiDevice});
        reasonProc.waitForFinished(3000);
        const QString reasonOut = QString::fromUtf8(reasonProc.readAllStandardOutput()).trimmed();
        return "WiFi hardware was detected but isn't usable right now "
               "(NetworkManager reports: " + reasonOut + "). Try restarting "
               "this device.";
    }

    return QString(); // device present, not blocked, not "unavailable" - whatever failed is something else (e.g. just no networks in range)
}
