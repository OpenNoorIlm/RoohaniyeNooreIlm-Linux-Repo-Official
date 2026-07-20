// BrightnessBackend: screen backlight control via /sys/class/backlight.
// Reading is always plain (world-readable sysfs). Writing the backlight
// device's `brightness` file is root-owned 0644 on stock Debian/Ubuntu-
// family images (no udev rule granting the `video` group write access
// out of the box), so a direct write from this process normally fails
// with EACCES - setBrightness() tries a direct write first (works for
// free on any machine where such a udev rule DOES exist, e.g. after
// InstallerBackend's install script adds one - see its bootloader stage)
// and falls back to `sudo -n sh -c "echo N > path"` otherwise (was
// `pkexec` - switched because this kiosk session has no graphical
// polkit auth agent, so pkexec just hangs/fails silently instead of
// prompting; see continue.md "Installer freeze/hang bug"). The fallback
// relies on the roohaniye user's passwordless NOPASSWD sudo, same as
// the installer and app center.
#pragma once

#include <QObject>
#include <QString>

class BrightnessBackend : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool available READ available NOTIFY availableChanged)
    Q_PROPERTY(int brightness READ brightness NOTIFY brightnessChanged) // 0-100

public:
    explicit BrightnessBackend(QObject *parent = nullptr);

    bool available() const { return m_available; }
    int brightness() const { return m_brightnessPct; }

    // percent clamped to 0-100. No-op if !available().
    Q_INVOKABLE void setBrightness(int percent);
    Q_INVOKABLE void increase(int stepPercent = 5);
    Q_INVOKABLE void decrease(int stepPercent = 5);

signals:
    void availableChanged();
    void brightnessChanged();

private:
    void detectDevice();
    void refresh(); // re-read current brightness from sysfs into m_brightnessPct
    bool writeRaw(int rawValue);

    bool m_available = false;
    QString m_devicePath;   // e.g. /sys/class/backlight/amdgpu_bl1
    int m_maxRaw = 0;
    int m_brightnessPct = 100;
};
