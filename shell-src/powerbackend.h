// PowerBackend: restart/shutdown via systemctl. No sudo needed for these —
// systemd's logind/polkit policy allows a logged-in user session to issue
// these by default on most distros (including Debian minimal + a display
// session), same as a "Shut Down" button in any desktop environment.
#pragma once

#include <QObject>

class PowerBackend : public QObject
{
    Q_OBJECT
public:
    explicit PowerBackend(QObject *parent = nullptr) : QObject(parent) {}

    Q_INVOKABLE void shutdown();
    Q_INVOKABLE void restart();
};
