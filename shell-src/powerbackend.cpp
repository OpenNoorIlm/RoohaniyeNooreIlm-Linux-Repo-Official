#include "powerbackend.h"
#include <QProcess>

void PowerBackend::shutdown()
{
    QProcess::startDetached("systemctl", {"poweroff"});
}

void PowerBackend::restart()
{
    QProcess::startDetached("systemctl", {"reboot"});
}
