// StorageBackend: detects removable storage (USB flash drives, microSD/SD
// cards) using the same "shell out / poll the filesystem, no D-Bus lib"
// philosophy as WifiBackend (nmcli) and PowerBackend (systemctl) - here
// that means polling the standard auto-mount directories Ubuntu's
// file manager / udisks2 already populate (/media/$USER, /run/media/$USER)
// rather than talking to UDisks2 over D-Bus directly. Simpler, and works
// with whatever desktop auto-mount mechanism the target image ends up
// using.
//
// Drives the "Database Connector" home-screen tile's enabled/disabled
// state (see DbConnectorBackend + qml/DatabaseConnector.qml) - the tile
// only lights up once storagePresent is true.
#pragma once

#include <QObject>
#include <QVariantList>
#include <QTimer>

class StorageBackend : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool storagePresent READ storagePresent NOTIFY devicesChanged)
    Q_PROPERTY(QVariantList devices READ devices NOTIFY devicesChanged)

public:
    explicit StorageBackend(QObject *parent = nullptr);

    bool storagePresent() const { return !m_devices.isEmpty(); }
    // Each entry: { label, path }
    QVariantList devices() const { return m_devices; }

    Q_INVOKABLE void refresh();

signals:
    void devicesChanged();
    void deviceAdded(const QString &path, const QString &label);
    void deviceRemoved(const QString &path);

private:
    QVariantList m_devices;
    QTimer m_pollTimer;
};
