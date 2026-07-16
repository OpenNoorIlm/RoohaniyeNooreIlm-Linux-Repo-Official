// ReminderBackend: simple recurring reminders (e.g. "Read Quran" daily
// at a set time, "Read Hadith" on weekdays, etc). Deliberately basic -
// no snooze, no per-instance history beyond "did this fire today" -
// matching the rest of this project's philosophy of shelling out to/
// wrapping simple mechanisms rather than building a full scheduling
// engine. Polled via a QTimer (checked every 30s) rather than using
// systemd timers/at, since reminders only need to fire while the shell
// itself is running (kiosk device, always on) - no need for the extra
// complexity of external OS-level scheduling.
//
// Persisted as a single JSON array (via QSettings, same storage this
// project already uses everywhere else) rather than one QSettings key
// per field, since the list is small and each reminder is a small
// self-contained record - easier to read/write/migrate as one blob.
#pragma once

#include <QObject>
#include <QVariantList>
#include <QVariantMap>
#include <QSettings>
#include <QTimer>

class ReminderBackend : public QObject
{
    Q_OBJECT
public:
    explicit ReminderBackend(QObject *parent = nullptr);

    // Each reminder: {id, title, hour, minute, days (array of 0=Sun..6=Sat), enabled}
    Q_INVOKABLE QVariantList reminders() const;

    // days: array of ints 0(Sun)-6(Sat). Empty array = fires every day.
    Q_INVOKABLE int addReminder(const QString &title, int hour, int minute, const QVariantList &days);
    Q_INVOKABLE void updateReminder(int id, const QString &title, int hour, int minute, const QVariantList &days);
    Q_INVOKABLE void removeReminder(int id);
    Q_INVOKABLE void setEnabled(int id, bool enabled);

    // A few ready-made suggestions the QML "quick add" row can offer -
    // just title strings, the user still picks the time/days.
    Q_INVOKABLE QStringList suggestedTitles() const;

signals:
    // Fired once per reminder per day, the minute its time is reached
    // (while the app is running - a missed minute, e.g. device was off,
    // is NOT caught up/fired late).
    void reminderDue(int id, QString title);

private:
    void checkDue();
    void save();
    void load();

    QSettings m_settings;
    QVariantList m_reminders; // list of QVariantMap
    int m_nextId;
    QTimer m_pollTimer;
};
