// SystemInfoBackend: read-only system stats for the top status bar
// (clock/battery/wifi/volume glance) and the full System Info app.
// Same shell-out-or-sysfs philosophy as the other backends here
// (WifiBackend/PowerBackend/StorageBackend) - no extra libraries linked
// in, just /proc, /sys and QStorageInfo, all of which are always present
// on any Linux target regardless of what's installed. Battery is read
// directly from /sys/class/power_supply rather than via upower, since
// upower is a desktop-session dependency this kiosk image doesn't
// otherwise need (see continue.md "SystemInfoBackend" entry) - sysfs is
// populated by the kernel itself and needs no daemon running.
//
// Polls on its own QTimer (2s tick for the fast-changing values: CPU/mem/
// battery; disk usage is only refreshed every 5th tick since free space
// changes far more slowly and QStorageInfo::refresh() + stat()-ing every
// mount point is comparatively expensive to do every 2s for no benefit).
// Static, one-time values (CPU model/core count, GPU model, hostname,
// kernel version) are read once at construction and never re-read.
#pragma once

#include <QObject>
#include <QVariantList>
#include <QString>
#include <QTimer>

class SystemInfoBackend : public QObject
{
    Q_OBJECT
    // ---- Static (read once at startup) ----
    Q_PROPERTY(QString cpuModel READ cpuModel CONSTANT)
    Q_PROPERTY(int cpuCores READ cpuCores CONSTANT)
    Q_PROPERTY(QString gpuModel READ gpuModel CONSTANT)
    Q_PROPERTY(QString hostname READ hostname CONSTANT)
    Q_PROPERTY(QString kernelVersion READ kernelVersion CONSTANT)
    Q_PROPERTY(qint64 memTotalMB READ memTotalMB CONSTANT)

    // ---- Dynamic (refreshed on the poll timer) ----
    Q_PROPERTY(int cpuUsagePercent READ cpuUsagePercent NOTIFY cpuUsageChanged)
    Q_PROPERTY(qint64 memUsedMB READ memUsedMB NOTIFY memUsageChanged)
    Q_PROPERTY(int memUsagePercent READ memUsagePercent NOTIFY memUsageChanged)
    Q_PROPERTY(QString uptimeString READ uptimeString NOTIFY uptimeChanged)

    // ---- Battery (present may be false on a desktop/kiosk box with no
    // battery at all - the top bar hides the battery glyph entirely in
    // that case rather than showing a meaningless 0%) ----
    Q_PROPERTY(bool batteryPresent READ batteryPresent NOTIFY batteryChanged)
    Q_PROPERTY(int batteryPercent READ batteryPercent NOTIFY batteryChanged)
    Q_PROPERTY(bool batteryCharging READ batteryCharging NOTIFY batteryChanged)

    // ---- Disk usage across real (non-pseudo) mounted filesystems.
    // Each entry: { mount, device, totalMB, usedMB, percent } ----
    Q_PROPERTY(QVariantList diskUsage READ diskUsage NOTIFY diskUsageChanged)

public:
    explicit SystemInfoBackend(QObject *parent = nullptr);

    QString cpuModel() const { return m_cpuModel; }
    int cpuCores() const { return m_cpuCores; }
    QString gpuModel() const { return m_gpuModel; }
    QString hostname() const { return m_hostname; }
    QString kernelVersion() const { return m_kernelVersion; }
    qint64 memTotalMB() const { return m_memTotalMB; }

    int cpuUsagePercent() const { return m_cpuUsagePercent; }
    qint64 memUsedMB() const { return m_memUsedMB; }
    int memUsagePercent() const { return m_memUsagePercent; }
    QString uptimeString() const { return m_uptimeString; }

    bool batteryPresent() const { return m_batteryPresent; }
    int batteryPercent() const { return m_batteryPercent; }
    bool batteryCharging() const { return m_batteryCharging; }

    QVariantList diskUsage() const { return m_diskUsage; }

    // Force an immediate refresh of everything (including disk usage,
    // normally throttled to every 5th tick) - useful right when the
    // System Info screen is opened, so it doesn't show stale numbers
    // for up to ~10s while waiting for the next scheduled tick.
    Q_INVOKABLE void refreshNow();

signals:
    void cpuUsageChanged();
    void memUsageChanged();
    void uptimeChanged();
    void batteryChanged();
    void diskUsageChanged();

private:
    void readStaticInfo();
    void pollTick();
    void refreshCpuUsage();
    void refreshMemUsage();
    void refreshUptime();
    void refreshBattery();
    void refreshDiskUsage();

    // Static
    QString m_cpuModel = "Unknown CPU";
    int m_cpuCores = 1;
    QString m_gpuModel = "Unknown GPU";
    QString m_hostname;
    QString m_kernelVersion;
    qint64 m_memTotalMB = 0;

    // Dynamic
    int m_cpuUsagePercent = 0;
    qint64 m_memUsedMB = 0;
    int m_memUsagePercent = 0;
    QString m_uptimeString = "0m";

    bool m_batteryPresent = false;
    int m_batteryPercent = 0;
    bool m_batteryCharging = false;

    QVariantList m_diskUsage;

    // /proc/stat jiffie deltas for CPU% (a single sample is meaningless -
    // percent-busy only makes sense as a delta between two reads).
    qint64 m_prevIdle = 0;
    qint64 m_prevTotal = 0;

    QTimer m_pollTimer;
    int m_tickCount = 0;
};
