#include "systeminfobackend.h"

#include <QFile>
#include <QDir>
#include <QProcess>
#include <QSysInfo>
#include <QStorageInfo>
#include <QStringList>
#include <QRegularExpression>
#include <QFileInfo>

namespace {

QString readFileTrimmed(const QString &path)
{
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text)) return QString();
    return QString::fromUtf8(f.readAll()).trimmed();
}

// Splits /proc/stat's leading "cpu  ..." line into {idle, total} jiffies.
// idle here includes iowait, matching the standard "top"-style formula.
bool readCpuJiffies(qint64 &idleOut, qint64 &totalOut)
{
    QFile f("/proc/stat");
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text)) return false;
    const QString line = QString::fromUtf8(f.readLine());
    if (!line.startsWith("cpu ")) return false;

    const QStringList parts = line.simplified().split(' ', Qt::SkipEmptyParts);
    // parts[0] == "cpu", then user nice system idle iowait irq softirq steal guest guest_nice
    if (parts.size() < 5) return false;

    qint64 total = 0;
    for (int i = 1; i < parts.size(); ++i) total += parts[i].toLongLong();

    const qint64 idle = parts[4].toLongLong() + (parts.size() > 5 ? parts[5].toLongLong() : 0);

    idleOut = idle;
    totalOut = total;
    return true;
}

} // namespace

SystemInfoBackend::SystemInfoBackend(QObject *parent) : QObject(parent)
{
    readStaticInfo();

    // Prime the CPU-usage delta baseline so the very first tick doesn't
    // report a meaningless huge percentage (delta against zero).
    readCpuJiffies(m_prevIdle, m_prevTotal);

    refreshMemUsage();
    refreshUptime();
    refreshBattery();
    refreshDiskUsage();

    m_pollTimer.setInterval(2000);
    connect(&m_pollTimer, &QTimer::timeout, this, &SystemInfoBackend::pollTick);
    m_pollTimer.start();
}

void SystemInfoBackend::readStaticInfo()
{
    m_hostname = QSysInfo::machineHostName();
    m_kernelVersion = QSysInfo::kernelVersion();

    // ---- CPU model + core count from /proc/cpuinfo ----
    QFile cpuinfo("/proc/cpuinfo");
    if (cpuinfo.open(QIODevice::ReadOnly | QIODevice::Text)) {
        int cores = 0;
        static const QRegularExpression modelRe("^model name\\s*:\\s*(.+)$");
        while (!cpuinfo.atEnd()) {
            const QString line = QString::fromUtf8(cpuinfo.readLine()).trimmed();
            if (line.startsWith("processor")) {
                ++cores;
            } else if (m_cpuModel == "Unknown CPU") {
                const auto match = modelRe.match(line);
                if (match.hasMatch()) m_cpuModel = match.captured(1).trimmed();
            }
        }
        if (cores > 0) m_cpuCores = cores;
    }

    // ---- GPU model via lspci (best-effort - if lspci isn't installed,
    // stays "Unknown GPU" rather than blocking startup on it) ----
    QProcess lspci;
    lspci.start("lspci", QStringList());
    if (lspci.waitForFinished(2000)) {
        const QString out = QString::fromUtf8(lspci.readAllStandardOutput());
        const auto lines = out.split('\n');
        for (const QString &line : lines) {
            if (line.contains("VGA compatible controller", Qt::CaseInsensitive)
                || line.contains("3D controller", Qt::CaseInsensitive)) {
                const int colon = line.indexOf(": ");
                m_gpuModel = (colon >= 0) ? line.mid(colon + 2).trimmed() : line.trimmed();
                break;
            }
        }
    }

    // ---- Total RAM from /proc/meminfo (doesn't change at runtime, so
    // read once here rather than every poll tick) ----
    QFile meminfo("/proc/meminfo");
    if (meminfo.open(QIODevice::ReadOnly | QIODevice::Text)) {
        while (!meminfo.atEnd()) {
            const QString line = QString::fromUtf8(meminfo.readLine());
            if (line.startsWith("MemTotal:")) {
                const QStringList parts = line.simplified().split(' ');
                if (parts.size() >= 2) m_memTotalMB = parts[1].toLongLong() / 1024;
                break;
            }
        }
    }
}

void SystemInfoBackend::pollTick()
{
    ++m_tickCount;
    refreshCpuUsage();
    refreshMemUsage();
    refreshUptime();
    refreshBattery();

    // Disk usage every 5th tick (~10s) - free space doesn't change fast
    // enough to justify stat()-ing every mount point every 2s.
    if (m_tickCount % 5 == 0) refreshDiskUsage();
}

void SystemInfoBackend::refreshCpuUsage()
{
    qint64 idle = 0, total = 0;
    if (!readCpuJiffies(idle, total)) return;

    const qint64 deltaIdle = idle - m_prevIdle;
    const qint64 deltaTotal = total - m_prevTotal;
    m_prevIdle = idle;
    m_prevTotal = total;

    if (deltaTotal <= 0) return; // guard against div-by-zero on a too-fast repeat call

    const int pct = qBound(0, qRound(100.0 * (1.0 - double(deltaIdle) / double(deltaTotal))), 100);
    if (pct != m_cpuUsagePercent) {
        m_cpuUsagePercent = pct;
        emit cpuUsageChanged();
    }
}

void SystemInfoBackend::refreshMemUsage()
{
    QFile meminfo("/proc/meminfo");
    if (!meminfo.open(QIODevice::ReadOnly | QIODevice::Text)) return;

    qint64 total = 0, available = 0;
    while (!meminfo.atEnd()) {
        const QString line = QString::fromUtf8(meminfo.readLine());
        if (line.startsWith("MemTotal:")) {
            total = line.simplified().split(' ').value(1).toLongLong();
        } else if (line.startsWith("MemAvailable:")) {
            available = line.simplified().split(' ').value(1).toLongLong();
        }
        if (total && available) break;
    }
    if (total <= 0) return;

    const qint64 usedMB = qMax<qint64>(0, (total - available) / 1024);
    const int pct = qBound(0, qRound(100.0 * double(total - available) / double(total)), 100);

    bool changed = false;
    if (usedMB != m_memUsedMB) { m_memUsedMB = usedMB; changed = true; }
    if (pct != m_memUsagePercent) { m_memUsagePercent = pct; changed = true; }
    if (changed) emit memUsageChanged();
}

void SystemInfoBackend::refreshUptime()
{
    const QString raw = readFileTrimmed("/proc/uptime");
    if (raw.isEmpty()) return;

    const double seconds = raw.split(' ').value(0).toDouble();
    const qint64 totalMin = qint64(seconds) / 60;
    const qint64 days = totalMin / (60 * 24);
    const qint64 hours = (totalMin / 60) % 24;
    const qint64 mins = totalMin % 60;

    QString s;
    if (days > 0) s = QString("%1d %2h %3m").arg(days).arg(hours).arg(mins);
    else if (hours > 0) s = QString("%1h %2m").arg(hours).arg(mins);
    else s = QString("%1m").arg(mins);

    if (s != m_uptimeString) {
        m_uptimeString = s;
        emit uptimeChanged();
    }
}

void SystemInfoBackend::refreshBattery()
{
    QDir powerDir("/sys/class/power_supply");
    QStringList batteries = powerDir.entryList({"BAT*"}, QDir::Dirs | QDir::NoDotAndDotDot);

    bool present = !batteries.isEmpty();
    int pct = m_batteryPercent;
    bool charging = m_batteryCharging;

    if (present) {
        const QString base = powerDir.absoluteFilePath(batteries.first());
        const QString capacity = readFileTrimmed(base + "/capacity");
        const QString status = readFileTrimmed(base + "/status"); // Charging/Discharging/Full/Not charging/Unknown
        if (!capacity.isEmpty()) pct = qBound(0, capacity.toInt(), 100);
        charging = (status.compare("Charging", Qt::CaseInsensitive) == 0)
                || (status.compare("Full", Qt::CaseInsensitive) == 0);
    }

    bool changed = false;
    if (present != m_batteryPresent) { m_batteryPresent = present; changed = true; }
    if (pct != m_batteryPercent) { m_batteryPercent = pct; changed = true; }
    if (charging != m_batteryCharging) { m_batteryCharging = charging; changed = true; }
    if (changed) emit batteryChanged();
}

void SystemInfoBackend::refreshDiskUsage()
{
    QVariantList list;
    const auto volumes = QStorageInfo::mountedVolumes();
    for (const QStorageInfo &storage : volumes) {
        if (!storage.isValid() || !storage.isReady()) continue;
        if (storage.bytesTotal() <= 0) continue;

        const QString fsType = QString::fromUtf8(storage.fileSystemType());
        // Skip pseudo/virtual filesystems that would just clutter the
        // list with 0-byte-relevant or duplicate entries (tmpfs, devtmpfs,
        // squashfs live-ISO layers, overlay dupes, snap loop mounts).
        if (fsType.contains("tmpfs", Qt::CaseInsensitive)) continue;
        if (fsType.contains("squashfs", Qt::CaseInsensitive)) continue;
        if (fsType.contains("overlay", Qt::CaseInsensitive) && storage.rootPath() != "/") continue;
        if (storage.rootPath().startsWith("/snap/")) continue;

        const qint64 totalMB = storage.bytesTotal() / (1024 * 1024);
        const qint64 freeMB = storage.bytesAvailable() / (1024 * 1024);
        const qint64 usedMB = qMax<qint64>(0, totalMB - freeMB);
        const int pct = totalMB > 0 ? qBound(0, qRound(100.0 * double(usedMB) / double(totalMB)), 100) : 0;

        QVariantMap entry;
        entry["mount"] = storage.rootPath();
        entry["device"] = QString::fromUtf8(storage.device());
        entry["totalMB"] = totalMB;
        entry["usedMB"] = usedMB;
        entry["percent"] = pct;
        list.append(entry);
    }

    m_diskUsage = list;
    emit diskUsageChanged();
}

void SystemInfoBackend::refreshNow()
{
    refreshCpuUsage();
    refreshMemUsage();
    refreshUptime();
    refreshBattery();
    refreshDiskUsage();
}
