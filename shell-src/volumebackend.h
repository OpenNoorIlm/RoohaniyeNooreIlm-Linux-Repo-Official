// VolumeBackend: system audio volume/mute via `wpctl` (PipeWire's
// wpctl CLI - present on any Pipewire-based desktop, which is what
// modern Debian/Ubuntu-family images ship by default). Same
// shell-out philosophy as WifiBackend (nmcli)/PowerBackend (systemctl) -
// no direct PipeWire client library linkage needed. Unlike brightness,
// this needs no elevated privileges - a regular user session can always
// adjust its own audio server's volume.
#pragma once

#include <QObject>

class VolumeBackend : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool available READ available NOTIFY availableChanged)
    Q_PROPERTY(int volume READ volume NOTIFY volumeChanged) // 0-100, independent of mute
    Q_PROPERTY(bool muted READ muted NOTIFY mutedChanged)

public:
    explicit VolumeBackend(QObject *parent = nullptr);

    bool available() const { return m_available; }
    int volume() const { return m_volumePct; }
    bool muted() const { return m_muted; }

    Q_INVOKABLE void setVolume(int percent);
    Q_INVOKABLE void increase(int stepPercent = 5);
    Q_INVOKABLE void decrease(int stepPercent = 5);
    Q_INVOKABLE void setMuted(bool muted);
    Q_INVOKABLE void toggleMute();
    // Re-read current volume/mute from wpctl - call after external
    // changes (e.g. another app adjusted it) if you want to resync;
    // this backend does not poll continuously.
    Q_INVOKABLE void refresh();

signals:
    void availableChanged();
    void volumeChanged();
    void mutedChanged();

private:
    bool m_available = false;
    int m_volumePct = 100;
    bool m_muted = false;
};
