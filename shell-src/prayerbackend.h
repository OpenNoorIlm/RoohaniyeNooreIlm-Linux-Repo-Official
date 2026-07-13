// PrayerBackend: prayer time calculation + qibla bearing, with a
// manually-set location (no GPS on this hardware target - user picks
// from a short curated city list or enters lat/lon directly).
//
// Prayer time algorithm is a standard sun-position based method (the
// same approach used by most prayer-time apps/libraries - sun
// declination + equation of time from a low-order solar ephemeris,
// then hour-angle formulas for each prayer's sun-altitude threshold).
// Defaults to Muslim World League angles (Fajr 18 deg, Isha 17 deg) and
// Shafi/Maliki/Hanbali Asr shadow factor (1); both are user-adjustable
// preferences for those following a different school/authority.
//
// NOT handled: automatic timezone/DST lookup (the user sets a UTC
// offset manually alongside their location; DST transitions require
// updating it twice a year), high-latitude edge cases where the sun
// angle formulas have no solution (e.g. far north in summer - falls
// back to a fixed offset from Dhuhr in that case, which is the same
// "nearest latitude"/heuristic approach most simpler implementations
// use rather than the full set of high-latitude adjustment methods).
#pragma once

#include <QObject>
#include <QVariantMap>
#include <QVariantList>
#include <QSettings>

class PrayerBackend : public QObject
{
    Q_OBJECT
public:
    explicit PrayerBackend(QObject *parent = nullptr);

    // Location, persisted via QSettings.
    Q_INVOKABLE void setLocation(double lat, double lon, double tzOffsetHours, const QString &label);
    Q_INVOKABLE QVariantMap location() const; // {hasLocation, lat, lon, tzOffset, label}

    // Calculation method preferences, persisted.
    Q_INVOKABLE void setCalculationSettings(double fajrAngle, double ishaAngle, int asrFactor);
    Q_INVOKABLE QVariantMap calculationSettings() const;

    // A short curated list of major cities for quick location picking
    // (name, lat, lon, tzOffset - standard-time offset, NOT DST-adjusted).
    Q_INVOKABLE QVariantList cityList() const;

    // Returns fajr/sunrise/dhuhr/asr/maghrib/isha, each as {label, hhmm,
    // decimalHours}, using the currently-saved location + calculation
    // settings, for today's date (system clock).
    Q_INVOKABLE QVariantList prayerTimesToday() const;

    // Which of today's prayers is next, and how many minutes until it
    // (negative/rolls to tomorrow's Fajr if today's Isha has passed).
    Q_INVOKABLE QVariantMap nextPrayer() const;

    // Great-circle bearing (degrees clockwise from true north) from the
    // saved location to the Kaaba (21.4225 N, 39.8262 E).
    Q_INVOKABLE double qiblaBearing() const;

private:
    QVariantList computeTimesFor(double lat, double lon, double tzOffset,
                                  int year, int month, int day) const;

    mutable QSettings m_settings;
};
