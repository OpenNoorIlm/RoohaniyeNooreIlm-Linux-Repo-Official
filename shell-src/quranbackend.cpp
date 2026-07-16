#include "quranbackend.h"

#include <QSqlQuery>
#include <QSqlError>
#include <QSqlRecord>
#include <QVariant>
#include <QDebug>
#include <QFile>
#include <QDir>
#include <QStandardPaths>
#include <QRandomGenerator>
#include <QRegExp>
#include <QMap>

namespace {

// Recitation style + display name for each reciter_id actually present in
// audio_files. Two naming schemes coexist in the db (display-name style
// and lowercase "ar.xxx" codes) - these are genuinely different reciters/
// recording sessions, not duplicates, so all are listed as-is.
struct ReciterMeta {
    const char *id;
    const char *name;
    const char *style; // "Murattal" (measured) or "Mujawwad" (melodic)
};
static const ReciterMeta kReciterMeta[] = {
    {"Abdul Basit (Mujawwad)",      "Abdul Basit Abdus-Samad",  "Mujawwad"},
    {"ar.abdulbasitmurattal",       "Abdul Basit Abdus-Samad",  "Murattal"},
    {"Hani Ar-Rifai",               "Hani Ar-Rifai",            "Murattal"},
    {"Mishary Alafasy (Murattal)",  "Mishary Rashid Alafasy",   "Murattal"},
    {"ar.alafasy",                  "Mishary Rashid Alafasy",   "Murattal"},
    {"Sa`ud Ash-Shuraym",           "Sa'ud Ash-Shuraym",         "Murattal"},
    {"ar.abdurrahmaansudais",       "Abdurrahman As-Sudais",    "Murattal"},
    {"ar.minshawi",                 "Muhammad Siddiq Al-Minshawi", "Murattal"},
    {"ar.shaatree",                 "Abu Bakr Ash-Shatri",      "Murattal"},
};

// book -> display name for the two hadith collections actually in the
// db. Falls back to the raw book string (title-cased) for anything else,
// so an imported db with a different collection still works, just
// without a nicer display name.
static QString hadithBookDisplayName(const QString &book)
{
    if (book == "bukhari") return QStringLiteral("Sahih al-Bukhari");
    if (book == "muslim") return QStringLiteral("Sahih Muslim");
    if (book.isEmpty()) return book;
    QString out = book;
    out[0] = out[0].toUpper();
    return out;
}

struct SurahMeta {
    const char *transliteration;
    const char *arabic;
    const char *englishMeaning;
    bool medinan; // false = Meccan
};

// Static reference table: names + revelation place. The DB only stores
// verse text/surah numbers, no surah metadata, so this fills the gap.
// Indexed 1..114 (index 0 unused).
static const SurahMeta kSurahMeta[115] = {
    {"", "", "", false}, // unused
    {"Al-Fatihah", "الفاتحة", "The Opening", false},
    {"Al-Baqarah", "البقرة", "The Cow", true},
    {"Aal-E-Imran", "آل عمران", "The Family of Imran", true},
    {"An-Nisa", "النساء", "The Women", true},
    {"Al-Ma'idah", "المائدة", "The Table Spread", true},
    {"Al-An'am", "الأنعام", "The Cattle", false},
    {"Al-A'raf", "الأعراف", "The Heights", false},
    {"Al-Anfal", "الأنفال", "The Spoils of War", true},
    {"At-Tawbah", "التوبة", "The Repentance", true},
    {"Yunus", "يونس", "Jonah", false},
    {"Hud", "هود", "Hud", false},
    {"Yusuf", "يوسف", "Joseph", false},
    {"Ar-Ra'd", "الرعد", "The Thunder", true},
    {"Ibrahim", "ابراهيم", "Abraham", false},
    {"Al-Hijr", "الحجر", "The Rocky Tract", false},
    {"An-Nahl", "النحل", "The Bee", false},
    {"Al-Isra", "الإسراء", "The Night Journey", false},
    {"Al-Kahf", "الكهف", "The Cave", false},
    {"Maryam", "مريم", "Mary", false},
    {"Ta-Ha", "طه", "Ta-Ha", false},
    {"Al-Anbiya", "الأنبياء", "The Prophets", false},
    {"Al-Hajj", "الحج", "The Pilgrimage", true},
    {"Al-Mu'minun", "المؤمنون", "The Believers", false},
    {"An-Nur", "النور", "The Light", true},
    {"Al-Furqan", "الفرقان", "The Criterion", false},
    {"Ash-Shu'ara", "الشعراء", "The Poets", false},
    {"An-Naml", "النمل", "The Ants", false},
    {"Al-Qasas", "القصص", "The Stories", false},
    {"Al-Ankabut", "العنكبوت", "The Spider", false},
    {"Ar-Rum", "الروم", "The Romans", false},
    {"Luqman", "لقمان", "Luqman", false},
    {"As-Sajdah", "السجدة", "The Prostration", false},
    {"Al-Ahzab", "الأحزاب", "The Combined Forces", true},
    {"Saba", "سبأ", "Sheba", false},
    {"Fatir", "فاطر", "Originator", false},
    {"Ya-Sin", "يس", "Ya Sin", false},
    {"As-Saffat", "الصافات", "Those Who Set The Ranks", false},
    {"Sad", "ص", "The Letter Sad", false},
    {"Az-Zumar", "الزمر", "The Troops", false},
    {"Ghafir", "غافر", "The Forgiver", false},
    {"Fussilat", "فصلت", "Explained In Detail", false},
    {"Ash-Shuraa", "الشورى", "The Consultation", false},
    {"Az-Zukhruf", "الزخرف", "The Ornaments Of Gold", false},
    {"Ad-Dukhan", "الدخان", "The Smoke", false},
    {"Al-Jathiyah", "الجاثية", "The Crouching", false},
    {"Al-Ahqaf", "الأحقاف", "The Wind-Curved Sandhills", false},
    {"Muhammad", "محمد", "Muhammad", true},
    {"Al-Fath", "الفتح", "The Victory", true},
    {"Al-Hujurat", "الحجرات", "The Rooms", true},
    {"Qaf", "ق", "The Letter Qaf", false},
    {"Adh-Dhariyat", "الذاريات", "The Winnowing Winds", false},
    {"At-Tur", "الطور", "The Mount", false},
    {"An-Najm", "النجم", "The Star", false},
    {"Al-Qamar", "القمر", "The Moon", false},
    {"Ar-Rahman", "الرحمن", "The Beneficent", true},
    {"Al-Waqi'ah", "الواقعة", "The Inevitable", false},
    {"Al-Hadid", "الحديد", "The Iron", true},
    {"Al-Mujadila", "المجادلة", "The Pleading Woman", true},
    {"Al-Hashr", "الحشر", "The Exile", true},
    {"Al-Mumtahanah", "الممتحنة", "She That Is To Be Examined", true},
    {"As-Saf", "الصف", "The Ranks", true},
    {"Al-Jumu'ah", "الجمعة", "The Congregation, Friday", true},
    {"Al-Munafiqun", "المنافقون", "The Hypocrites", true},
    {"At-Taghabun", "التغابن", "The Mutual Disillusion", true},
    {"At-Talaq", "الطلاق", "Divorce", true},
    {"At-Tahrim", "التحريم", "The Prohibition", true},
    {"Al-Mulk", "الملك", "The Sovereignty", false},
    {"Al-Qalam", "القلم", "The Pen", false},
    {"Al-Haqqah", "الحاقة", "The Reality", false},
    {"Al-Ma'arij", "المعارج", "The Ascending Stairways", false},
    {"Nuh", "نوح", "Noah", false},
    {"Al-Jinn", "الجن", "The Jinn", false},
    {"Al-Muzzammil", "المزمل", "The Enshrouded One", false},
    {"Al-Muddaththir", "المدثر", "The Cloaked One", false},
    {"Al-Qiyamah", "القيامة", "The Resurrection", false},
    {"Al-Insan", "الانسان", "The Man", true},
    {"Al-Mursalat", "المرسلات", "The Emissaries", false},
    {"An-Naba", "النبأ", "The Tidings", false},
    {"An-Nazi'at", "النازعات", "Those Who Drag Forth", false},
    {"Abasa", "عبس", "He Frowned", false},
    {"At-Takwir", "التكوير", "The Overthrowing", false},
    {"Al-Infitar", "الإنفطار", "The Cleaving", false},
    {"Al-Mutaffifin", "المطففين", "The Defrauding", false},
    {"Al-Inshiqaq", "الإنشقاق", "The Sundering", false},
    {"Al-Buruj", "البروج", "The Mansions Of The Stars", false},
    {"At-Tariq", "الطارق", "The Morning Star", false},
    {"Al-A'la", "الأعلى", "The Most High", false},
    {"Al-Ghashiyah", "الغاشية", "The Overwhelming", false},
    {"Al-Fajr", "الفجر", "The Dawn", false},
    {"Al-Balad", "البلد", "The City", false},
    {"Ash-Shams", "الشمس", "The Sun", false},
    {"Al-Layl", "الليل", "The Night", false},
    {"Ad-Duhaa", "الضحى", "The Morning Hours", false},
    {"Ash-Sharh", "الشرح", "The Relief", false},
    {"At-Tin", "التين", "The Fig", false},
    {"Al-Alaq", "العلق", "The Clot", false},
    {"Al-Qadr", "القدر", "The Power", false},
    {"Al-Bayyinah", "البينة", "The Clear Proof", true},
    {"Az-Zalzalah", "الزلزلة", "The Earthquake", true},
    {"Al-Adiyat", "العاديات", "The Courser", false},
    {"Al-Qari'ah", "القارعة", "The Calamity", false},
    {"At-Takathur", "التكاثر", "The Rivalry In World Increase", false},
    {"Al-Asr", "العصر", "The Declining Day", false},
    {"Al-Humazah", "الهمزة", "The Traducer", false},
    {"Al-Fil", "الفيل", "The Elephant", false},
    {"Quraysh", "قريش", "Quraysh", false},
    {"Al-Ma'un", "الماعون", "The Small Kindnesses", false},
    {"Al-Kawthar", "الكوثر", "The Abundance", false},
    {"Al-Kafirun", "الكافرون", "The Disbelievers", false},
    {"An-Nasr", "النصر", "The Divine Support", true},
    {"Al-Masad", "المسد", "The Palm Fiber", false},
    {"Al-Ikhlas", "الإخلاص", "The Sincerity", false},
    {"Al-Falaq", "الفلق", "The Daybreak", false},
    {"An-Nas", "الناس", "Mankind", false},
};

} // namespace

QuranBackend::QuranBackend(QObject *parent)
    : QObject(parent)
    , m_settings(QStringLiteral("/opt/roohaniye/data/shell_settings.ini"), QSettings::IniFormat)
{
}

QuranBackend::~QuranBackend()
{
    if (m_quranDb.isOpen()) m_quranDb.close();
    if (m_hadithDb.isOpen()) m_hadithDb.close();
}

bool QuranBackend::openDatabases(const QString &quranTextDbPath,
                                  const QString &quranAudioDbPath,
                                  const QString &hadithDbPath)
{
    // Allow a previously-imported db (via the Database Connector app,
    // dbconnectorbackend.h) to override the bundled default, re-applied
    // fresh on every launch. quran_text.db can only be overridden this
    // way (needs a restart to take effect); audio/hadith overrides are
    // also applied live at import time via reattachAudioDb/reattachHadithDb
    // below, this just makes them stick across restarts too.
    QString effectiveTextPath = quranTextDbPath;
    const QString textOverride = m_settings.value("quranTextDbOverridePath").toString();
    if (!textOverride.isEmpty() && QFile::exists(textOverride)) {
        effectiveTextPath = textOverride;
        qDebug() << "Using imported Quran text DB override:" << effectiveTextPath;
    }

    QString effectiveAudioPath = quranAudioDbPath;
    const QString audioOverride = m_settings.value("audioDbOverridePath").toString();
    if (!audioOverride.isEmpty() && QFile::exists(audioOverride)) {
        effectiveAudioPath = audioOverride;
        qDebug() << "Using imported audio DB override:" << effectiveAudioPath;
    }

    QString effectiveHadithPath = hadithDbPath;
    const QString hadithOverride = m_settings.value("hadithDbOverridePath").toString();
    if (!hadithOverride.isEmpty() && QFile::exists(hadithOverride)) {
        effectiveHadithPath = hadithOverride;
        qDebug() << "Using imported hadith DB override:" << effectiveHadithPath;
    }

    if (!QFile::exists(effectiveTextPath)) {
        qWarning() << "Quran text DB not found at:" << effectiveTextPath;
    }
    if (!QFile::exists(effectiveAudioPath)) {
        qWarning() << "Quran audio DB not found at:" << effectiveAudioPath;
    }
    if (!QFile::exists(effectiveHadithPath)) {
        qWarning() << "Hadith DB not found at:" << effectiveHadithPath;
    }

    m_quranDb = QSqlDatabase::addDatabase("QSQLITE", "quran_conn");
    m_quranDb.setDatabaseName(effectiveTextPath);
    // Open read-only: this shell never writes to the scripture DBs.
    m_quranDb.setConnectOptions("QSQLITE_OPEN_READONLY");
    bool quranOk = m_quranDb.open();
    if (!quranOk) {
        qWarning() << "Failed to open Quran text DB:" << m_quranDb.lastError().text();
    } else if (QFile::exists(effectiveAudioPath)) {
        // Attach the (huge) audio db onto the same connection so existing
        // verses<->audio_files joins keep working, just qualified with
        // "audiodb." - see the class comment in quranbackend.h. Attached
        // databases inherit the read-only mode of the main connection, so
        // this stays read-only same as the text db.
        QSqlQuery attachQ(m_quranDb);
        attachQ.prepare("ATTACH DATABASE ? AS audiodb");
        attachQ.addBindValue(effectiveAudioPath);
        if (!attachQ.exec()) {
            // Audio DB present but failed to attach (corrupt/wrong format)
            // - genuinely a problem, but still don't take verse reading
            // down with it. Log loudly and continue text-only.
            qWarning() << "Failed to attach Quran audio DB (text reading still works):" << attachQ.lastError().text();
            m_audioDbAttached = false;
        } else {
            m_audioDbAttached = true;
        }
    } else {
        // Deliberately NOT a failure condition: the "lite" ISO variant
        // ships without quran_audio.db by design (see live-build/README.md),
        // relying on the Database Connector app to import it later. Verse
        // text/navigation/hadith all work fine without it; only audio
        // playback/reciterList() are unavailable until an import happens,
        // and those already fail gracefully per-call (empty list / no-op)
        // rather than needing this attach to have succeeded.
        qWarning() << "Quran audio DB not present (expected for the lite build) - text reading still works, import via Database Connector to enable audio.";
        m_audioDbAttached = false;
    }

    m_hadithDb = QSqlDatabase::addDatabase("QSQLITE", "hadith_conn");
    m_hadithDb.setDatabaseName(effectiveHadithPath);
    m_hadithDb.setConnectOptions("QSQLITE_OPEN_READONLY");
    const bool hadithOk = m_hadithDb.open();
    if (!hadithOk) {
        qWarning() << "Failed to open Hadith DB:" << m_hadithDb.lastError().text();
    }

    qDebug() << "openDatabases: quranOk=" << quranOk << "hadithOk=" << hadithOk;
    return quranOk && hadithOk;
}

bool QuranBackend::reattachAudioDb(const QString &newPath)
{
    if (!m_quranDb.isOpen() || !QFile::exists(newPath)) return false;

    QSqlQuery detachQ(m_quranDb);
    detachQ.exec("DETACH DATABASE audiodb"); // ignore failure - fine if nothing was attached

    QSqlQuery attachQ(m_quranDb);
    attachQ.prepare("ATTACH DATABASE ? AS audiodb");
    attachQ.addBindValue(newPath);
    if (!attachQ.exec()) {
        qWarning() << "reattachAudioDb: ATTACH failed:" << attachQ.lastError().text();
        return false;
    }

    // Don't commit to a wrong/empty attachment - verify it actually has
    // the table this app needs before persisting the choice.
    QSqlQuery check(m_quranDb);
    check.exec("SELECT name FROM audiodb.sqlite_master WHERE type='table' AND name='audio_files'");
    if (!check.next()) {
        qWarning() << "reattachAudioDb: no audio_files table in" << newPath;
        QSqlQuery cleanup(m_quranDb);
        cleanup.exec("DETACH DATABASE audiodb");
        return false;
    }

    m_settings.setValue("audioDbOverridePath", newPath);
    return true;
}

bool QuranBackend::reattachHadithDb(const QString &newPath)
{
    if (!QFile::exists(newPath)) return false;

    m_hadithDb.close();
    m_hadithDb.setDatabaseName(newPath);
    m_hadithDb.setConnectOptions("QSQLITE_OPEN_READONLY");
    if (!m_hadithDb.open()) {
        qWarning() << "reattachHadithDb: open failed:" << m_hadithDb.lastError().text();
        return false;
    }

    QSqlQuery check(m_hadithDb);
    check.exec("SELECT name FROM sqlite_master WHERE type='table' AND name='hadiths'");
    if (!check.next()) {
        qWarning() << "reattachHadithDb: no hadiths table in" << newPath;
        m_hadithDb.close();
        return false;
    }

    m_settings.setValue("hadithDbOverridePath", newPath);
    return true;
}

QVariantMap QuranBackend::verse(int surah, int ayah) const
{
    QVariantMap result;
    if (!m_quranDb.isOpen()) return result;

    QSqlQuery q(m_quranDb);
    q.prepare("SELECT text_uthmani, text_sahih, text_kanzuliman, text_jalalayn, juz, page, "
              "manzil, ruku, hizb_quarter, sajda, sajda_obligatory "
              "FROM verses WHERE surah = ? AND ayah = ? LIMIT 1");
    q.addBindValue(surah);
    q.addBindValue(ayah);
    if (q.exec() && q.next()) {
        result["arabic"] = q.value(0).toString();
        result["english"] = q.value(1).toString();
        result["urdu"] = q.value(2).toString();
        result["tafsir"] = q.value(3).toString();
        result["juz"] = q.value(4).toInt();
        result["page"] = q.value(5).toInt();
        result["manzil"] = q.value(6).toInt();
        result["ruku"] = q.value(7).toInt();
        result["hizbQuarter"] = q.value(8).toInt();
        result["sajda"] = q.value(9).toInt() != 0;
        result["sajdaObligatory"] = q.value(10).toInt() != 0;
        result["surah"] = surah;
        result["ayah"] = ayah;
    }
    return result;
}

QVariantList QuranBackend::surahList() const
{
    QVariantList out;
    if (!m_quranDb.isOpen()) return out;

    QSqlQuery q(m_quranDb);
    q.exec("SELECT surah, MAX(ayah) FROM verses GROUP BY surah ORDER BY surah");
    while (q.next()) {
        const int surah = q.value(0).toInt();
        QVariantMap m;
        m["surah"] = surah;
        m["ayahCount"] = q.value(1).toInt();
        if (surah >= 1 && surah <= 114) {
            const SurahMeta &meta = kSurahMeta[surah];
            m["nameTransliteration"] = QString::fromUtf8(meta.transliteration);
            m["nameArabic"] = QString::fromUtf8(meta.arabic);
            m["nameEnglish"] = QString::fromUtf8(meta.englishMeaning);
            m["revelationPlace"] = meta.medinan ? QStringLiteral("Medinan") : QStringLiteral("Meccan");
        }
        out.append(m);
    }
    return out;
}

QVariantMap QuranBackend::surahInfo(int surah) const
{
    QVariantMap m;
    if (surah < 1 || surah > 114) return m;

    const SurahMeta &meta = kSurahMeta[surah];
    m["surah"] = surah;
    m["nameTransliteration"] = QString::fromUtf8(meta.transliteration);
    m["nameArabic"] = QString::fromUtf8(meta.arabic);
    m["nameEnglish"] = QString::fromUtf8(meta.englishMeaning);
    m["revelationPlace"] = meta.medinan ? QStringLiteral("Medinan") : QStringLiteral("Meccan");

    if (m_quranDb.isOpen()) {
        QSqlQuery q(m_quranDb);
        q.prepare("SELECT MAX(ayah) FROM verses WHERE surah = ?");
        q.addBindValue(surah);
        if (q.exec() && q.next()) {
            m["ayahCount"] = q.value(0).toInt();
        }
    }
    return m;
}

QString QuranBackend::audioBase64(int surah, int ayah, const QString &reciterId) const
{
    if (!m_quranDb.isOpen() || !m_audioDbAttached) return {};

    QSqlQuery q(m_quranDb);
    q.prepare("SELECT audio_data FROM audiodb.audio_files af "
              "JOIN verses v ON v.id = af.verse_id "
              "WHERE v.surah = ? AND v.ayah = ? AND af.reciter_id = ? LIMIT 1");
    q.addBindValue(surah);
    q.addBindValue(ayah);
    q.addBindValue(reciterId);
    if (q.exec() && q.next()) {
        return QString::fromLatin1(q.value(0).toByteArray().toBase64());
    }
    return {};
}

namespace {
const char *kVerseCols =
    "text_uthmani, text_sahih, text_kanzuliman, text_jalalayn, juz, page, "
    "manzil, ruku, hizb_quarter, sajda, sajda_obligatory, surah, ayah";

const char *kHadithCols = "id, book, hadith_num, topic, english, urdu, arabic";
}

QVariantMap QuranBackend::rowToVerseMap(QSqlQuery &q) const
{
    QVariantMap result;
    result["arabic"] = q.value(0).toString();
    result["english"] = q.value(1).toString();
    result["urdu"] = q.value(2).toString();
    result["tafsir"] = q.value(3).toString();
    result["juz"] = q.value(4).toInt();
    result["page"] = q.value(5).toInt();
    result["manzil"] = q.value(6).toInt();
    result["ruku"] = q.value(7).toInt();
    result["hizbQuarter"] = q.value(8).toInt();
    result["sajda"] = q.value(9).toInt() != 0;
    result["sajdaObligatory"] = q.value(10).toInt() != 0;
    result["surah"] = q.value(11).toInt();
    result["ayah"] = q.value(12).toInt();
    return result;
}

QVariantMap QuranBackend::rowToHadithMap(QSqlQuery &q) const
{
    QVariantMap m;
    m["id"] = q.value(0).toInt();
    m["book"] = q.value(1).toString();
    m["bookDisplayName"] = hadithBookDisplayName(q.value(1).toString());
    m["hadithNum"] = q.value(2).toString();
    m["topic"] = q.value(3).toString();
    m["english"] = q.value(4).toString();
    m["urdu"] = q.value(5).toString();
    m["arabic"] = q.value(6).toString();
    return m;
}

QVariantList QuranBackend::versesInSurah(int surah) const
{
    QVariantList out;
    if (!m_quranDb.isOpen()) return out;

    QSqlQuery q(m_quranDb);
    q.prepare(QString("SELECT %1 FROM verses WHERE surah = ? ORDER BY ayah").arg(kVerseCols));
    q.addBindValue(surah);
    if (!q.exec()) {
        qWarning() << "versesInSurah failed:" << q.lastError().text();
        return out;
    }
    while (q.next()) out.append(rowToVerseMap(q));
    return out;
}

QVariantList QuranBackend::versesInJuz(int juz) const
{
    QVariantList out;
    if (!m_quranDb.isOpen()) return out;

    QSqlQuery q(m_quranDb);
    q.prepare(QString("SELECT %1 FROM verses WHERE juz = ? ORDER BY surah, ayah").arg(kVerseCols));
    q.addBindValue(juz);
    if (!q.exec()) {
        qWarning() << "versesInJuz failed:" << q.lastError().text();
        return out;
    }
    while (q.next()) out.append(rowToVerseMap(q));
    return out;
}

QVariantList QuranBackend::versesInPage(int page) const
{
    QVariantList out;
    if (!m_quranDb.isOpen()) return out;

    QSqlQuery q(m_quranDb);
    q.prepare(QString("SELECT %1 FROM verses WHERE page = ? ORDER BY surah, ayah").arg(kVerseCols));
    q.addBindValue(page);
    if (!q.exec()) {
        qWarning() << "versesInPage failed:" << q.lastError().text();
        return out;
    }
    while (q.next()) out.append(rowToVerseMap(q));
    return out;
}

QVariantList QuranBackend::versesInManzil(int manzil) const
{
    QVariantList out;
    if (!m_quranDb.isOpen()) return out;

    QSqlQuery q(m_quranDb);
    q.prepare(QString("SELECT %1 FROM verses WHERE manzil = ? ORDER BY surah, ayah").arg(kVerseCols));
    q.addBindValue(manzil);
    if (!q.exec()) {
        qWarning() << "versesInManzil failed:" << q.lastError().text();
        return out;
    }
    while (q.next()) out.append(rowToVerseMap(q));
    return out;
}

QVariantList QuranBackend::versesInRuku(int ruku) const
{
    QVariantList out;
    if (!m_quranDb.isOpen()) return out;

    QSqlQuery q(m_quranDb);
    q.prepare(QString("SELECT %1 FROM verses WHERE ruku = ? ORDER BY surah, ayah").arg(kVerseCols));
    q.addBindValue(ruku);
    if (!q.exec()) {
        qWarning() << "versesInRuku failed:" << q.lastError().text();
        return out;
    }
    while (q.next()) out.append(rowToVerseMap(q));
    return out;
}

int QuranBackend::totalPages() const
{
    if (!m_quranDb.isOpen()) return 0;
    QSqlQuery q(m_quranDb);
    if (q.exec("SELECT MAX(page) FROM verses") && q.next()) {
        return q.value(0).toInt();
    }
    return 0;
}

int QuranBackend::totalRukus() const
{
    if (!m_quranDb.isOpen()) return 0;
    QSqlQuery q(m_quranDb);
    if (q.exec("SELECT MAX(ruku) FROM verses") && q.next()) {
        return q.value(0).toInt();
    }
    return 0;
}

QVariantMap QuranBackend::quranStats() const
{
    QVariantMap m;
    m["surahs"] = 114;
    m["ayahs"] = 6236;
    m["juz"] = 30;
    m["pages"] = totalPages();
    m["manzils"] = 7;
    m["rukus"] = totalRukus();
    m["hizbQuarters"] = 240;
    if (m_quranDb.isOpen()) {
        QSqlQuery q(m_quranDb);
        if (q.exec("SELECT COUNT(*) FROM verses WHERE sajda = 1") && q.next()) {
            m["sajdas"] = q.value(0).toInt();
        }
        if (q.exec("SELECT COUNT(*) FROM verses WHERE sajda = 1 AND sajda_obligatory = 1") && q.next()) {
            m["sajdasObligatory"] = q.value(0).toInt();
        }
    }
    return m;
}

QVariantMap QuranBackend::randomVerse() const
{
    QVariantMap result;
    if (!m_quranDb.isOpen()) return result;

    QSqlQuery bounds(m_quranDb);
    if (!bounds.exec("SELECT MIN(id), MAX(id) FROM verses") || !bounds.next()) return result;
    const qint64 minId = bounds.value(0).toLongLong();
    const qint64 maxId = bounds.value(1).toLongLong();
    if (maxId < minId) return result;
    const qint64 targetId = minId + (QRandomGenerator::global()->generate64() % (maxId - minId + 1));

    QSqlQuery q(m_quranDb);
    q.prepare(QString("SELECT %1 FROM verses WHERE id >= ? ORDER BY id LIMIT 1").arg(kVerseCols));
    q.addBindValue(targetId);
    if (q.exec() && q.next()) {
        result = rowToVerseMap(q);
    }
    return result;
}

QVariantMap QuranBackend::nextVerse(int surah, int ayah) const
{
    QVariantMap result;
    if (!m_quranDb.isOpen()) return result;

    QSqlQuery countQ(m_quranDb);
    countQ.prepare("SELECT MAX(ayah) FROM verses WHERE surah = ?");
    countQ.addBindValue(surah);
    int ayahCount = 0;
    if (countQ.exec() && countQ.next()) ayahCount = countQ.value(0).toInt();

    int nextSurah = surah;
    int nextAyah = ayah + 1;
    if (nextAyah > ayahCount) {
        nextSurah = surah + 1;
        nextAyah = 1;
        if (nextSurah > 114) {
            // Wrap back to the very start of the Quran.
            nextSurah = 1;
            nextAyah = 1;
        }
    }

    QSqlQuery q(m_quranDb);
    q.prepare(QString("SELECT %1 FROM verses WHERE surah = ? AND ayah = ? LIMIT 1").arg(kVerseCols));
    q.addBindValue(nextSurah);
    q.addBindValue(nextAyah);
    if (q.exec() && q.next()) {
        result = rowToVerseMap(q);
    }
    return result;
}

QVariantMap QuranBackend::previousVerse(int surah, int ayah) const
{
    QVariantMap result;
    if (!m_quranDb.isOpen()) return result;

    int prevSurah = surah;
    int prevAyah = ayah - 1;
    if (prevAyah < 1) {
        prevSurah = surah - 1;
        if (prevSurah < 1) {
            // Wrap to the very last ayah of the Quran (114:6).
            prevSurah = 114;
            prevAyah = 6;
        } else {
            QSqlQuery countQ(m_quranDb);
            countQ.prepare("SELECT MAX(ayah) FROM verses WHERE surah = ?");
            countQ.addBindValue(prevSurah);
            if (countQ.exec() && countQ.next()) prevAyah = countQ.value(0).toInt();
        }
    }

    QSqlQuery q(m_quranDb);
    q.prepare(QString("SELECT %1 FROM verses WHERE surah = ? AND ayah = ? LIMIT 1").arg(kVerseCols));
    q.addBindValue(prevSurah);
    q.addBindValue(prevAyah);
    if (q.exec() && q.next()) {
        result = rowToVerseMap(q);
    }
    return result;
}

QVariantList QuranBackend::reciterList() const
{
    QVariantList out;
    if (!m_quranDb.isOpen() || !m_audioDbAttached) return out;

    QSqlQuery q(m_quranDb);
    if (!q.exec("SELECT DISTINCT reciter_id FROM audiodb.audio_files ORDER BY reciter_id")) {
        qWarning() << "reciterList failed:" << q.lastError().text();
        return out;
    }
    while (q.next()) {
        const QString id = q.value(0).toString();
        QVariantMap m;
        m["id"] = id;
        m["name"] = id;
        m["style"] = "";
        for (const auto &meta : kReciterMeta) {
            if (id == QString::fromUtf8(meta.id)) {
                m["name"] = QString::fromUtf8(meta.name);
                m["style"] = QString::fromUtf8(meta.style);
                break;
            }
        }
        out.append(m);
    }
    return out;
}

QVariantList QuranBackend::versesForSelection(const QVariantList &items) const
{
    // Key by surah*10000+ayah so a QMap gives us both de-duplication and
    // natural Quran order for free, regardless of the order the caller's
    // selection items (mixed juz/surah/ayah) were made in.
    QMap<int, QVariantMap> ordered;
    auto addVerse = [&ordered](const QVariantMap &v) {
        if (v.isEmpty()) return;
        const int s = v.value("surah").toInt();
        const int a = v.value("ayah").toInt();
        if (s <= 0 || a <= 0) return;
        ordered.insert(s * 10000 + a, v);
    };

    for (const QVariant &itemVar : items) {
        const QVariantMap item = itemVar.toMap();
        const QString type = item.value("type").toString();
        if (type == "surah") {
            const QVariantList verses = versesInSurah(item.value("surah").toInt());
            for (const QVariant &vv : verses) addVerse(vv.toMap());
        } else if (type == "juz") {
            const QVariantList verses = versesInJuz(item.value("juz").toInt());
            for (const QVariant &vv : verses) addVerse(vv.toMap());
        } else if (type == "ayah") {
            addVerse(verse(item.value("surah").toInt(), item.value("ayah").toInt()));
        }
    }

    QVariantList result;
    for (auto it = ordered.constBegin(); it != ordered.constEnd(); ++it) {
        QVariantMap m;
        m["surah"] = it.value().value("surah");
        m["ayah"] = it.value().value("ayah");
        result.append(m);
    }
    return result;
}

QString QuranBackend::audioFilePath(int surah, int ayah, const QString &reciterId) const
{
    if (!m_quranDb.isOpen() || !m_audioDbAttached) {
        qWarning() << "audioFilePath: audio database not attached (lite install?) — skipping";
        return {};
    }

    const QString cacheDir = QStandardPaths::writableLocation(QStandardPaths::CacheLocation)
                              + "/roohaniye-audio";
    QDir().mkpath(cacheDir);

    // Sanitize reciterId for use in a filename (some ids have spaces/parens/backtick).
    QString safeReciter = reciterId;
    safeReciter.replace(QRegExp("[^A-Za-z0-9_.-]"), "_");

    const QString path = QString("%1/%2_%3_%4.mp3").arg(cacheDir).arg(surah).arg(ayah).arg(safeReciter);
    if (QFile::exists(path)) return path;

    QSqlQuery q(m_quranDb);
    q.prepare("SELECT audio_data FROM audiodb.audio_files af "
              "JOIN verses v ON v.id = af.verse_id "
              "WHERE v.surah = ? AND v.ayah = ? AND af.reciter_id = ? LIMIT 1");
    q.addBindValue(surah);
    q.addBindValue(ayah);
    q.addBindValue(reciterId);
    if (!q.exec() || !q.next()) {
        qWarning() << "audioFilePath: no audio for" << surah << ayah << reciterId;
        return {};
    }

    QFile f(path);
    if (!f.open(QIODevice::WriteOnly)) {
        qWarning() << "audioFilePath: failed to write cache file" << path;
        return {};
    }
    f.write(q.value(0).toByteArray());
    f.close();
    return path;
}

void QuranBackend::saveProgress(int surah, int ayah)
{
    m_settings.setValue("progress/surah", surah);
    m_settings.setValue("progress/ayah", ayah);
    m_settings.sync();
}

QVariantMap QuranBackend::lastProgress() const
{
    QVariantMap m;
    m["surah"] = m_settings.value("progress/surah", 1).toInt();
    m["ayah"] = m_settings.value("progress/ayah", 1).toInt();
    return m;
}

void QuranBackend::setPreference(const QString &key, const QVariant &value)
{
    m_settings.setValue("prefs/" + key, value);
    m_settings.sync();
}

QVariant QuranBackend::preference(const QString &key, const QVariant &defaultValue) const
{
    return m_settings.value("prefs/" + key, defaultValue);
}

QVariantMap QuranBackend::randomHadith() const
{
    QVariantMap result;
    if (!m_hadithDb.isOpen()) {
        qWarning() << "randomHadith: hadith DB is not open";
        return result;
    }

    // Avoid ORDER BY RANDOM(): that forces SQLite to scan + sort every row
    // (including large text columns) just to pick one, which gets slow as
    // the table grows. Instead: find the id range once, pick a random id,
    // and look it up directly by primary key (O(1) via the rowid index).
    // If that exact id doesn't exist (gaps from FTS bookkeeping etc), fall
    // back to the next id that does.
    QSqlQuery bounds(m_hadithDb);
    if (!bounds.exec("SELECT MIN(id), MAX(id) FROM hadiths") || !bounds.next()) {
        qWarning() << "randomHadith: failed to read id bounds:" << bounds.lastError().text();
        return result;
    }
    const qint64 minId = bounds.value(0).toLongLong();
    const qint64 maxId = bounds.value(1).toLongLong();
    if (maxId < minId) return result;

    const qint64 targetId = minId + (QRandomGenerator::global()->generate64() % (maxId - minId + 1));

    QSqlQuery q(m_hadithDb);
    q.prepare("SELECT * FROM hadiths WHERE id >= ? ORDER BY id LIMIT 1");
    q.addBindValue(targetId);
    if (!q.exec()) {
        qWarning() << "randomHadith query failed:" << q.lastError().text();
        return result;
    }
    if (q.next()) {
        const QSqlRecord rec = q.record();
        for (int i = 0; i < rec.count(); ++i) {
            result[rec.fieldName(i)] = q.value(i);
        }
    } else {
        qWarning() << "randomHadith: query returned no rows";
    }
    return result;
}

QVariantList QuranBackend::hadithBookList() const
{
    QVariantList out;
    if (!m_hadithDb.isOpen()) return out;

    QSqlQuery q(m_hadithDb);
    if (!q.exec("SELECT book, COUNT(*) FROM hadiths GROUP BY book ORDER BY MIN(id)")) {
        qWarning() << "hadithBookList failed:" << q.lastError().text();
        return out;
    }
    while (q.next()) {
        QVariantMap m;
        const QString book = q.value(0).toString();
        m["book"] = book;
        m["displayName"] = hadithBookDisplayName(book);
        m["count"] = q.value(1).toInt();
        out.append(m);
    }
    return out;
}

QVariantList QuranBackend::hadithTopics(const QString &book) const
{
    QVariantList out;
    if (!m_hadithDb.isOpen()) return out;

    QSqlQuery q(m_hadithDb);
    // Ordered by MIN(id) so topics come back in the collection's original
    // chapter order (e.g. Bukhari's "Revelation" first), not alphabetical.
    q.prepare("SELECT topic, COUNT(*) FROM hadiths WHERE book = ? "
              "GROUP BY topic ORDER BY MIN(id)");
    q.addBindValue(book);
    if (!q.exec()) {
        qWarning() << "hadithTopics failed:" << q.lastError().text();
        return out;
    }
    while (q.next()) {
        QVariantMap m;
        m["topic"] = q.value(0).toString();
        m["count"] = q.value(1).toInt();
        out.append(m);
    }
    return out;
}

QVariantList QuranBackend::hadithsByTopic(const QString &book, const QString &topic) const
{
    QVariantList out;
    if (!m_hadithDb.isOpen()) return out;

    QSqlQuery q(m_hadithDb);
    q.prepare(QString("SELECT %1 FROM hadiths WHERE book = ? AND topic = ? ORDER BY id").arg(kHadithCols));
    q.addBindValue(book);
    q.addBindValue(topic);
    if (!q.exec()) {
        qWarning() << "hadithsByTopic failed:" << q.lastError().text();
        return out;
    }
    while (q.next()) out.append(rowToHadithMap(q));
    return out;
}

QVariantList QuranBackend::hadithsInBook(const QString &book, int afterId, int limit) const
{
    QVariantList out;
    if (!m_hadithDb.isOpen()) return out;
    if (limit <= 0) limit = 40;

    QSqlQuery q(m_hadithDb);
    q.prepare(QString("SELECT %1 FROM hadiths WHERE book = ? AND id > ? ORDER BY id LIMIT ?").arg(kHadithCols));
    q.addBindValue(book);
    q.addBindValue(afterId);
    q.addBindValue(limit);
    if (!q.exec()) {
        qWarning() << "hadithsInBook failed:" << q.lastError().text();
        return out;
    }
    while (q.next()) out.append(rowToHadithMap(q));
    return out;
}

QVariantMap QuranBackend::hadithById(int id) const
{
    QVariantMap result;
    if (!m_hadithDb.isOpen()) return result;

    QSqlQuery q(m_hadithDb);
    q.prepare(QString("SELECT %1 FROM hadiths WHERE id = ? LIMIT 1").arg(kHadithCols));
    q.addBindValue(id);
    if (q.exec() && q.next()) {
        result = rowToHadithMap(q);
    }
    return result;
}

QVariantList QuranBackend::searchHadiths(const QString &query, int limit) const
{
    QVariantList out;
    if (!m_hadithDb.isOpen()) return out;
    if (limit <= 0) limit = 30;

    // Build a safe FTS5 MATCH expression: split into tokens, quote each
    // one (so punctuation/FTS operators inside a token can't break the
    // query or be interpreted as syntax) and prefix-match it, joined with
    // implicit AND. e.g. `believer's deed` -> `"believer's"* "deed"*`.
    const QStringList rawTokens = query.split(QRegExp("\\s+"), Qt::SkipEmptyParts);
    if (rawTokens.isEmpty()) return out;

    QStringList matchParts;
    for (QString tok : rawTokens) {
        tok.replace('"', "\"\""); // escape embedded quotes for FTS5's own quoting
        matchParts << QString("\"%1\"*").arg(tok);
    }
    const QString matchExpr = matchParts.join(' ');

    // kHadithCols is unqualified (fine for the plain single-table queries
    // above), but hadiths_fts is an external-content FTS5 table that
    // mirrors english/urdu/arabic - joined and unqualified, those three
    // columns are ambiguous between "f" and "h", which SQLite rejects at
    // prepare time. Qt's QSQLITE driver then surfaces that prepare
    // failure as a misleading "Parameter count mismatch" instead of the
    // real "ambiguous column name" error. Fully qualify every column
    // with h. to resolve it.
    QString qualifiedCols = QString("h.") + QString(kHadithCols).replace(", ", ", h.");
    QSqlQuery q(m_hadithDb);
    q.prepare(QString("SELECT %1 FROM hadiths_fts f JOIN hadiths h ON h.id = f.rowid "
                       "WHERE hadiths_fts MATCH ? ORDER BY rank LIMIT ?").arg(qualifiedCols));
    q.addBindValue(matchExpr);
    q.addBindValue(limit);
    if (!q.exec()) {
        qWarning() << "searchHadiths failed:" << q.lastError().text() << "expr:" << matchExpr;
        return out;
    }
    while (q.next()) out.append(rowToHadithMap(q));
    return out;
}

QVariantList QuranBackend::hadithsForSelection(const QVariantList &items) const
{
    // Key by id so a QMap gives de-duplication + ascending order for
    // free, mirroring versesForSelection()'s approach.
    QMap<int, QVariantMap> ordered;
    auto addHadith = [&ordered](const QVariantMap &h) {
        if (h.isEmpty()) return;
        const int id = h.value("id").toInt();
        if (id <= 0) return;
        ordered.insert(id, h);
    };

    for (const QVariant &itemVar : items) {
        const QVariantMap item = itemVar.toMap();
        const QString type = item.value("type").toString();
        if (type == "topic") {
            const QVariantList hs = hadithsByTopic(item.value("book").toString(), item.value("topic").toString());
            for (const QVariant &hv : hs) addHadith(hv.toMap());
        } else if (type == "hadith") {
            addHadith(hadithById(item.value("id").toInt()));
        }
    }

    QVariantList result;
    for (auto it = ordered.constBegin(); it != ordered.constEnd(); ++it) {
        result.append(it.value());
    }
    return result;
}

void QuranBackend::saveHadithProgress(int id)
{
    m_settings.setValue("hadithProgress/id", id);
    m_settings.sync();
}

QVariantMap QuranBackend::lastHadithProgress() const
{
    const int id = m_settings.value("hadithProgress/id", 0).toInt();
    if (id <= 0) return QVariantMap();
    return hadithById(id);
}
