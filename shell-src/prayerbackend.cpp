// PrayerBackend implementation.
//
// Prayer-time math: standard sun-position (low-order solar ephemeris ->
// declination + equation of time) and hour-angle formulas, the same
// general approach used by most prayer-time calculators. See
// prayerbackend.h for the algorithm summary and known limitations.
#include "prayerbackend.h"

#include <QDateTime>
#include <QtMath>
#include <cmath>

namespace {

constexpr double kKaabaLat = 21.4225;
constexpr double kKaabaLon = 39.8262;

double rad(double deg) { return deg * M_PI / 180.0; }
double deg(double r) { return r * 180.0 / M_PI; }

// Wraps an hour value into [0, 24).
double fixHour(double h)
{
    h = std::fmod(h, 24.0);
    if (h < 0) h += 24.0;
    return h;
}

// Julian Day Number at 0h UTC for a given Gregorian calendar date.
double julianDay(int year, int month, int day)
{
    if (month <= 2) { year -= 1; month += 12; }
    const int a = year / 100;
    const int b = 2 - a + a / 4;
    return std::floor(365.25 * (year + 4716)) + std::floor(30.6001 * (month + 1))
           + day + b - 1524.5;
}

// Sun declination (deg) and equation of time (hours) for a Julian Day.
void sunPosition(double jd, double &declDeg, double &eqtHours)
{
    const double d = jd - 2451545.0;
    const double g = fixHour(357.529 + 0.98560028 * d / 15.0) * 15.0; // mean anomaly, deg [0,360)
    const double q = fixHour(280.459 + 0.98564736 * d / 15.0) * 15.0; // mean longitude, deg
    double l = q + 1.915 * std::sin(rad(g)) + 0.020 * std::sin(rad(2 * g)); // ecliptic longitude
    l = std::fmod(l, 360.0);
    if (l < 0) l += 360.0;

    const double e = 23.439 - 0.00000036 * d; // obliquity of the ecliptic

    double ra = deg(std::atan2(std::cos(rad(e)) * std::sin(rad(l)), std::cos(rad(l)))) / 15.0;
    ra = fixHour(ra) * 15.0; // right ascension, deg, same convention as q

    declDeg = deg(std::asin(std::sin(rad(e)) * std::sin(rad(l))));

    double eqt = q / 15.0 - ra / 15.0;
    // Keep eqt in a sane range around 0 (it should always be small, but
    // guard against the 24h wraparound landing it near +/-24).
    if (eqt > 12.0) eqt -= 24.0;
    if (eqt < -12.0) eqt += 24.0;
    eqtHours = eqt;
}

// Hour angle (hours from solar noon) for a target sun altitude (deg;
// negative = below horizon, e.g. -18 for astronomical twilight).
// Returns NaN if the sun never reaches that altitude on this day at
// this latitude (polar day/night) - caller must handle the fallback.
double hourAngleForAltitude(double altitudeDeg, double latDeg, double declDeg)
{
    const double cosH = (std::sin(rad(altitudeDeg)) - std::sin(rad(latDeg)) * std::sin(rad(declDeg)))
                         / (std::cos(rad(latDeg)) * std::cos(rad(declDeg)));
    if (cosH < -1.0 || cosH > 1.0) return std::nan("");
    return deg(std::acos(cosH)) / 15.0;
}

QVariantMap makeEntry(const QString &label, double decimalHours)
{
    decimalHours = fixHour(decimalHours);
    int h = int(decimalHours);
    int m = int(std::round((decimalHours - h) * 60.0));
    if (m == 60) { m = 0; h = (h + 1) % 24; }

    QVariantMap m1;
    m1["label"] = label;
    m1["hhmm"] = QString("%1:%2").arg(h, 2, 10, QChar('0')).arg(m, 2, 10, QChar('0'));
    m1["decimalHours"] = decimalHours;
    return m1;
}

} // namespace

PrayerBackend::PrayerBackend(QObject *parent)
    : QObject(parent)
    , m_settings(QStringLiteral("/opt/roohaniye/data/shell_settings.ini"), QSettings::IniFormat)
{
}

void PrayerBackend::setLocation(double lat, double lon, double tzOffsetHours, const QString &label)
{
    m_settings.setValue("prayer/lat", lat);
    m_settings.setValue("prayer/lon", lon);
    m_settings.setValue("prayer/tzOffset", tzOffsetHours);
    m_settings.setValue("prayer/label", label);
    m_settings.setValue("prayer/hasLocation", true);
    m_settings.sync();
}

QVariantMap PrayerBackend::location() const
{
    QVariantMap m;
    m["hasLocation"] = m_settings.value("prayer/hasLocation", false).toBool();
    m["lat"] = m_settings.value("prayer/lat", 0.0).toDouble();
    m["lon"] = m_settings.value("prayer/lon", 0.0).toDouble();
    m["tzOffset"] = m_settings.value("prayer/tzOffset", 0.0).toDouble();
    m["label"] = m_settings.value("prayer/label", QString()).toString();
    return m;
}

void PrayerBackend::setCalculationSettings(double fajrAngle, double ishaAngle, int asrFactor)
{
    m_settings.setValue("prayer/fajrAngle", fajrAngle);
    m_settings.setValue("prayer/ishaAngle", ishaAngle);
    m_settings.setValue("prayer/asrFactor", asrFactor);
    m_settings.sync();
}

QVariantMap PrayerBackend::calculationSettings() const
{
    QVariantMap m;
    // Defaults: Muslim World League (Fajr 18deg/Isha 17deg), Shafi/
    // Maliki/Hanbali Asr (shadow factor 1) - see prayerbackend.h.
    m["fajrAngle"] = m_settings.value("prayer/fajrAngle", 18.0).toDouble();
    m["ishaAngle"] = m_settings.value("prayer/ishaAngle", 17.0).toDouble();
    m["asrFactor"] = m_settings.value("prayer/asrFactor", 1).toInt();
    return m;
}

QVariantList PrayerBackend::cityList() const
{
    // name, lat, lon, tzOffset (standard time, NOT DST-adjusted - see
    // header comment). Curated: the two Haramain cities first, then a
    // spread of major cities across regions with a significant Muslim
    // population/readership.
    static const struct { const char *name; double lat, lon, tz; } kCities[] = {
        { "Makkah, Saudi Arabia",     21.4225,   39.8262,  3.0 },
        { "Madinah, Saudi Arabia",    24.4672,   39.6112,  3.0 },
        { "Istanbul, Turkey",         41.0082,   28.9784,  3.0 },
        { "Cairo, Egypt",             30.0444,   31.2357,  2.0 },
        { "Dubai, UAE",               25.2048,   55.2708,  4.0 },
        { "Riyadh, Saudi Arabia",     24.7136,   46.6753,  3.0 },
        { "Karachi, Pakistan",        24.8607,   67.0011,  5.0 },
        { "Lahore, Pakistan",         31.5497,   74.3436,  5.0 },
        { "Delhi, India",             28.7041,   77.1025,  5.5 },
        { "Mysuru, India",            12.2958,   76.6394,  5.5 },
        { "Dhaka, Bangladesh",        23.8103,   90.4125,  6.0 },
        { "Jakarta, Indonesia",       -6.2088,  106.8456,  7.0 },
        { "Kuala Lumpur, Malaysia",    3.1390,  101.6869,  8.0 },
        { "London, United Kingdom",   51.5072,   -0.1276,  0.0 },
        { "New York, United States",  40.7128,  -74.0060, -5.0 },
        { "Toronto, Canada",          43.6532,  -79.3832, -5.0 },
        { "Sydney, Australia",       -33.8688,  151.2093, 10.0 },
    };

    QVariantList list;
    for (const auto &c : kCities) {
        QVariantMap m;
        m["name"] = QString::fromUtf8(c.name);
        m["lat"] = c.lat;
        m["lon"] = c.lon;
        m["tzOffset"] = c.tz;
        list.append(m);
    }
    return list;
}

QVariantList PrayerBackend::computeTimesFor(double lat, double lon, double tzOffset,
                                             int year, int month, int day) const
{
    const auto calc = calculationSettings();
    const double fajrAngle = calc["fajrAngle"].toDouble();
    const double ishaAngle = calc["ishaAngle"].toDouble();
    const int asrFactor = calc["asrFactor"].toInt();

    const double jd = julianDay(year, month, day);
    double declDeg = 0.0, eqtHours = 0.0;
    sunPosition(jd, declDeg, eqtHours);

    // Local solar noon (Dhuhr), in the location's own clock time.
    const double noon = fixHour(12.0 - eqtHours - lon / 15.0 + tzOffset);

    // Sunrise/Sunset use the standard ~0.833deg depression (accounts
    // for the sun's apparent radius + average atmospheric refraction).
    // This can still fail in genuine polar day/night, but is solvable
    // across nearly the whole inhabited world year-round, so it's the
    // anchor the Fajr/Isha fallback below is built from.
    const double sunriseH = hourAngleForAltitude(-0.833, lat, declDeg);
    const bool sunriseOk = !std::isnan(sunriseH);
    const double sunrise = sunriseOk ? (noon - sunriseH) : fixHour(noon - 0.5);
    const double maghrib = sunriseOk ? (noon + sunriseH) : fixHour(noon + 0.5);

    // Length of the night (Maghrib to next Fajr's sunrise), used by the
    // high-latitude fallback below.
    double nightLength = 24.0 - fixHour(maghrib - sunrise);
    if (nightLength <= 0.0 || nightLength > 24.0) nightLength = 12.0; // guard

    const double fajrH = hourAngleForAltitude(-fajrAngle, lat, declDeg);
    // High-latitude fallback for Fajr/Isha (angle formula has no
    // solution - e.g. astronomical twilight never fully ends around
    // midsummer this far north): the "angle-based method" used by
    // several prayer-time calculators for exactly this case - scale the
    // requested angle against the night's actual length instead of the
    // (nonexistent) fixed sun-angle solution, anchored to sunrise/
    // maghrib so Fajr always stays before sunrise and Isha after
    // maghrib. See prayerbackend.h's "NOT handled" note.
    const double fajr = !std::isnan(fajrH)
        ? (noon - fajrH)
        : fixHour(sunrise - nightLength * (fajrAngle / 60.0));

    const double dhuhr = noon;

    const double asrAltitude = deg(std::atan(1.0 / (asrFactor + std::tan(rad(std::fabs(lat - declDeg))))));
    const double asrH = hourAngleForAltitude(asrAltitude, lat, declDeg);
    // Asr's own formula essentially never fails in practice (its target
    // altitude is well above the horizon), but guard anyway rather than
    // ever emitting NaN into the UI.
    const double asr = !std::isnan(asrH) ? (noon + asrH) : fixHour(noon + (maghrib - noon) * 0.6);

    const double ishaH = hourAngleForAltitude(-ishaAngle, lat, declDeg);
    const double isha = !std::isnan(ishaH)
        ? (noon + ishaH)
        : fixHour(maghrib + nightLength * (ishaAngle / 60.0));

    QVariantList list;
    list.append(makeEntry("Fajr", fajr));
    list.append(makeEntry("Sunrise", sunrise));
    list.append(makeEntry("Dhuhr", dhuhr));
    list.append(makeEntry("Asr", asr));
    list.append(makeEntry("Maghrib", maghrib));
    list.append(makeEntry("Isha", isha));
    return list;
}

QVariantList PrayerBackend::prayerTimesToday() const
{
    const auto loc = location();
    if (!loc["hasLocation"].toBool()) return {};

    const QDate today = QDateTime::currentDateTimeUtc()
                             .addSecs(qint64(loc["tzOffset"].toDouble() * 3600))
                             .date();
    return computeTimesFor(loc["lat"].toDouble(), loc["lon"].toDouble(),
                            loc["tzOffset"].toDouble(),
                            today.year(), today.month(), today.day());
}

QVariantMap PrayerBackend::nextPrayer() const
{
    QVariantMap result;
    const auto loc = location();
    if (!loc["hasLocation"].toBool()) {
        result["hasLocation"] = false;
        return result;
    }
    result["hasLocation"] = true;

    const double tzOffset = loc["tzOffset"].toDouble();
    const QDateTime nowUtc = QDateTime::currentDateTimeUtc();
    const QDateTime localNow = nowUtc.addSecs(qint64(tzOffset * 3600));
    const double nowHours = localNow.time().hour() + localNow.time().minute() / 60.0
                             + localNow.time().second() / 3600.0;

    const QVariantList todayTimes = prayerTimesToday();
    for (const QVariant &v : todayTimes) {
        const QVariantMap entry = v.toMap();
        const double t = entry["decimalHours"].toDouble();
        if (t > nowHours) {
            result["label"] = entry["label"];
            result["hhmm"] = entry["hhmm"];
            result["minutesUntil"] = int(std::round((t - nowHours) * 60.0));
            result["isTomorrow"] = false;
            return result;
        }
    }

    // Everything today has passed - next prayer is tomorrow's Fajr.
    const QDate tomorrow = localNow.date().addDays(1);
    const QVariantList tomorrowTimes = computeTimesFor(
        loc["lat"].toDouble(), loc["lon"].toDouble(), tzOffset,
        tomorrow.year(), tomorrow.month(), tomorrow.day());
    const QVariantMap fajr = tomorrowTimes.first().toMap();
    const double t = fajr["decimalHours"].toDouble();
    result["label"] = fajr["label"];
    result["hhmm"] = fajr["hhmm"];
    result["minutesUntil"] = int(std::round(((24.0 - nowHours) + t) * 60.0));
    result["isTomorrow"] = true;
    return result;
}

double PrayerBackend::qiblaBearing() const
{
    const auto loc = location();
    if (!loc["hasLocation"].toBool()) return 0.0;

    const double lat1 = rad(loc["lat"].toDouble());
    const double lon1 = rad(loc["lon"].toDouble());
    const double lat2 = rad(kKaabaLat);
    const double lon2 = rad(kKaabaLon);
    const double dLon = lon2 - lon1;

    const double y = std::sin(dLon) * std::cos(lat2);
    const double x = std::cos(lat1) * std::sin(lat2) - std::sin(lat1) * std::cos(lat2) * std::cos(dLon);
    double bearing = deg(std::atan2(y, x));
    bearing = std::fmod(bearing + 360.0, 360.0);
    return bearing;
}
