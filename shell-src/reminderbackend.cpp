#include "reminderbackend.h"
#include <QDateTime>
#include <QJsonDocument>
#include <QJsonArray>
#include <QJsonObject>

ReminderBackend::ReminderBackend(QObject *parent)
    : QObject(parent)
    , m_settings("/opt/roohaniye/data/shell_settings.ini", QSettings::IniFormat)
    , m_nextId(1)
{
    load();

    m_pollTimer.setInterval(30000); // 30s - fine granularity for a minute-resolution schedule without busy-polling
    connect(&m_pollTimer, &QTimer::timeout, this, &ReminderBackend::checkDue);
    m_pollTimer.start();
    checkDue(); // catch a reminder due right at startup, don't wait 30s
}

void ReminderBackend::load()
{
    QString json = m_settings.value("reminders/list", "[]").toString();
    QJsonDocument doc = QJsonDocument::fromJson(json.toUtf8());
    m_reminders.clear();
    if (doc.isArray()) {
        for (const QJsonValue &v : doc.array()) {
            m_reminders.append(v.toObject().toVariantMap());
        }
    }
    m_nextId = m_settings.value("reminders/nextId", 1).toInt();
}

void ReminderBackend::save()
{
    QJsonArray arr;
    for (const QVariant &r : m_reminders) {
        arr.append(QJsonObject::fromVariantMap(r.toMap()));
    }
    m_settings.setValue("reminders/list", QString::fromUtf8(QJsonDocument(arr).toJson(QJsonDocument::Compact)));
    m_settings.setValue("reminders/nextId", m_nextId);
    m_settings.sync();
}

QVariantList ReminderBackend::reminders() const
{
    return m_reminders;
}

int ReminderBackend::addReminder(const QString &title, int hour, int minute, const QVariantList &days)
{
    QVariantMap r;
    int id = m_nextId++;
    r["id"] = id;
    r["title"] = title;
    r["hour"] = hour;
    r["minute"] = minute;
    r["days"] = days;
    r["enabled"] = true;
    r["lastFiredDate"] = "";
    m_reminders.append(r);
    save();
    return id;
}

void ReminderBackend::updateReminder(int id, const QString &title, int hour, int minute, const QVariantList &days)
{
    for (int i = 0; i < m_reminders.size(); ++i) {
        QVariantMap r = m_reminders[i].toMap();
        if (r["id"].toInt() == id) {
            r["title"] = title;
            r["hour"] = hour;
            r["minute"] = minute;
            r["days"] = days;
            m_reminders[i] = r;
            save();
            return;
        }
    }
}

void ReminderBackend::removeReminder(int id)
{
    for (int i = 0; i < m_reminders.size(); ++i) {
        if (m_reminders[i].toMap()["id"].toInt() == id) {
            m_reminders.removeAt(i);
            save();
            return;
        }
    }
}

void ReminderBackend::setEnabled(int id, bool enabled)
{
    for (int i = 0; i < m_reminders.size(); ++i) {
        QVariantMap r = m_reminders[i].toMap();
        if (r["id"].toInt() == id) {
            r["enabled"] = enabled;
            m_reminders[i] = r;
            save();
            return;
        }
    }
}

QStringList ReminderBackend::suggestedTitles() const
{
    return { "Read Quran", "Read Hadith", "Morning Adhkar", "Evening Adhkar" };
}

void ReminderBackend::checkDue()
{
    QDateTime now = QDateTime::currentDateTime();
    int curHour = now.time().hour();
    int curMinute = now.time().minute();
    // Qt::DayOfWeek is 1=Monday..7=Sunday; convert to 0=Sunday..6=Saturday
    // to match the QML day-checkbox convention (Sun-first week, common
    // in prayer/reminder app UIs).
    int qtDow = now.date().dayOfWeek(); // 1-7
    int curDow = qtDow % 7; // Sunday(7)->0, Monday(1)->1, ... Saturday(6)->6
    QString today = now.date().toString("yyyy-MM-dd");

    bool changed = false;
    for (int i = 0; i < m_reminders.size(); ++i) {
        QVariantMap r = m_reminders[i].toMap();
        if (!r["enabled"].toBool()) continue;
        if (r["hour"].toInt() != curHour || r["minute"].toInt() != curMinute) continue;
        if (r["lastFiredDate"].toString() == today) continue; // already fired today

        QVariantList days = r["days"].toList();
        bool dayMatches = days.isEmpty(); // empty = every day
        for (const QVariant &d : days) {
            if (d.toInt() == curDow) { dayMatches = true; break; }
        }
        if (!dayMatches) continue;

        r["lastFiredDate"] = today;
        m_reminders[i] = r;
        changed = true;
        emit reminderDue(r["id"].toInt(), r["title"].toString());
    }
    if (changed) save();
}
