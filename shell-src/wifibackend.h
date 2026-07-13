// WifiBackend: thin wrapper around `nmcli` so we don't need to link against
// NetworkManager's D-Bus API directly. Simpler, and nmcli is present on any
// Debian-based image with NetworkManager installed (which we need anyway
// for a normal user to get online at all).
#pragma once

#include <QObject>
#include <QVariantList>
#include <QProcess>

class WifiBackend : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantList networks READ networks NOTIFY networksChanged)
    Q_PROPERTY(bool scanning READ scanning NOTIFY scanningChanged)
    Q_PROPERTY(QString statusMessage READ statusMessage NOTIFY statusChanged)
    Q_PROPERTY(bool wifiEnabled READ wifiEnabled NOTIFY wifiEnabledChanged)

public:
    explicit WifiBackend(QObject *parent = nullptr);

    QVariantList networks() const { return m_networks; }
    bool scanning() const { return m_scanning; }
    QString statusMessage() const { return m_statusMessage; }
    bool wifiEnabled() const { return m_wifiEnabled; }

    Q_INVOKABLE void scan();
    Q_INVOKABLE void connectToNetwork(const QString &ssid, const QString &password);
    Q_INVOKABLE void setWifiEnabled(bool enabled);
    Q_INVOKABLE void refreshWifiState();

signals:
    void networksChanged();
    void scanningChanged();
    void statusChanged();
    void wifiEnabledChanged();
    void connectFinished(bool success, const QString &message);

private:
    void setScanning(bool b);
    void setStatus(const QString &s);

    QVariantList m_networks;
    bool m_scanning = false;
    bool m_wifiEnabled = true;
    QString m_statusMessage;
};
