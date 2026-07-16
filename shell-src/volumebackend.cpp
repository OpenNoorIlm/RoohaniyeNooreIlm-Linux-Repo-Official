#include "volumebackend.h"

#include <QProcess>
#include <QRegularExpression>
#include <QStandardPaths>

namespace {
bool haveWpctl()
{
    return !QStandardPaths::findExecutable("wpctl").isEmpty();
}
}

VolumeBackend::VolumeBackend(QObject *parent) : QObject(parent)
{
    m_available = haveWpctl();
    if (m_available) refresh();
}

void VolumeBackend::refresh()
{
    if (!m_available) return;

    QProcess p;
    p.start("wpctl", {"get-volume", "@DEFAULT_AUDIO_SINK@"});
    if (!p.waitForFinished(3000)) return;
    const QString out = QString::fromUtf8(p.readAllStandardOutput()).trimmed();

    // Expected: "Volume: 0.88" or "Volume: 0.88 [MUTED]"
    static const QRegularExpression re("Volume:\\s*([0-9.]+)");
    const auto match = re.match(out);
    if (!match.hasMatch()) return;

    const double frac = match.captured(1).toDouble();
    const int pct = qBound(0, qRound(frac * 100.0), 100); // wpctl allows >100% boost; clamp for the UI
    const bool muted = out.contains("[MUTED]");

    bool changed = false;
    if (pct != m_volumePct) { m_volumePct = pct; changed = true; emit volumeChanged(); }
    Q_UNUSED(changed);
    if (muted != m_muted) { m_muted = muted; emit mutedChanged(); }
}

void VolumeBackend::setVolume(int percent)
{
    if (!m_available) return;
    percent = qBound(0, percent, 100);

    QProcess::execute("wpctl", {"set-volume", "@DEFAULT_AUDIO_SINK@", QString::number(percent) + "%"});

    if (percent != m_volumePct) {
        m_volumePct = percent;
        emit volumeChanged();
    }
}

void VolumeBackend::increase(int stepPercent)
{
    setVolume(m_volumePct + stepPercent);
}

void VolumeBackend::decrease(int stepPercent)
{
    setVolume(m_volumePct - stepPercent);
}

void VolumeBackend::setMuted(bool mutedState)
{
    if (!m_available) return;
    QProcess::execute("wpctl", {"set-mute", "@DEFAULT_AUDIO_SINK@", mutedState ? "1" : "0"});
    if (mutedState != m_muted) {
        m_muted = mutedState;
        emit mutedChanged();
    }
}

void VolumeBackend::toggleMute()
{
    setMuted(!m_muted);
}
