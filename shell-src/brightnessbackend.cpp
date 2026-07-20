#include "brightnessbackend.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QProcess>
#include <QTextStream>

BrightnessBackend::BrightnessBackend(QObject *parent) : QObject(parent)
{
    detectDevice();
    if (m_available) refresh();
}

void BrightnessBackend::detectDevice()
{
    QDir dir("/sys/class/backlight");
    const QStringList entries = dir.entryList(QDir::Dirs | QDir::NoDotAndDotDot);
    if (entries.isEmpty()) {
        m_available = false;
        return;
    }
    // Just take the first backlight device - real hardware normally only
    // exposes one (the internal panel); a machine with more than one
    // (e.g. dual-GPU) would need a picker, not something to guess at.
    m_devicePath = "/sys/class/backlight/" + entries.first();

    QFile maxFile(m_devicePath + "/max_brightness");
    if (!maxFile.open(QIODevice::ReadOnly)) {
        m_available = false;
        return;
    }
    bool ok = false;
    m_maxRaw = QString::fromUtf8(maxFile.readAll()).trimmed().toInt(&ok);
    maxFile.close();

    m_available = ok && m_maxRaw > 0;
}

void BrightnessBackend::refresh()
{
    QFile curFile(m_devicePath + "/brightness");
    if (!curFile.open(QIODevice::ReadOnly)) return;
    bool ok = false;
    const int raw = QString::fromUtf8(curFile.readAll()).trimmed().toInt(&ok);
    curFile.close();
    if (!ok || m_maxRaw <= 0) return;

    const int pct = qRound((raw * 100.0) / m_maxRaw);
    if (pct != m_brightnessPct) {
        m_brightnessPct = pct;
        emit brightnessChanged();
    }
}

bool BrightnessBackend::writeRaw(int rawValue)
{
    const QString path = m_devicePath + "/brightness";

    // Try a direct write first - succeeds for free if a udev rule has
    // granted the `video` group write access (see class comment).
    {
        QFile f(path);
        if (f.open(QIODevice::WriteOnly | QIODevice::Text)) {
            QTextStream out(&f);
            out << rawValue;
            f.close();
            return true;
        }
    }

    // Fall back to a single privileged write via sudo.
    // NOTE: was "pkexec" - changed because pkexec needs a graphical
    // polkit auth agent, which doesn't exist in this kiosk session (see
    // continue.md, "Installer freeze/hang bug"). Same failure mode here:
    // pkexec could block for the full 15s timeout on every debounced
    // slider write instead of failing fast. `-n` (non-interactive) makes
    // sudo fail immediately instead of hanging if NOPASSWD isn't set up.
    QProcess p;
    p.start("sudo", {"-n", "sh", "-c", QString("echo %1 > %2").arg(rawValue).arg(path)});
    if (!p.waitForFinished(15000)) return false;
    return p.exitCode() == 0;
}

void BrightnessBackend::setBrightness(int percent)
{
    if (!m_available) return;
    percent = qBound(0, percent, 100);
    const int raw = qRound((percent / 100.0) * m_maxRaw);

    if (writeRaw(raw)) {
        if (percent != m_brightnessPct) {
            m_brightnessPct = percent;
            emit brightnessChanged();
        }
    }
}

void BrightnessBackend::increase(int stepPercent)
{
    setBrightness(m_brightnessPct + stepPercent);
}

void BrightnessBackend::decrease(int stepPercent)
{
    setBrightness(m_brightnessPct - stepPercent);
}
