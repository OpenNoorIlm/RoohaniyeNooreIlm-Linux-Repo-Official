// QuranBackend: thin read layer over quran_text.db, quran_audio.db, and
// hadiths.db. Exposed to QML so the home screen / reader views can query
// verses, audio blobs, and hadiths without any SQL living in QML.
//
// quran_text.db (verses only, ~1MB) and quran_audio.db (audio_files +
// word_timings, tens of GB) used to be one combined file
// (quran_audio_embedded.db). They were split so that text-only reading/
// navigation queries - which run on basically every screen - never have
// to touch the same file as the huge audio BLOBs, which are only read
// during actual recitation playback. See scripts/split_quran_db.py.
//
// Both files are opened on ONE QSqlDatabase connection: quran_text.db is
// the main database, and quran_audio.db is attached to it at runtime via
// `ATTACH DATABASE ... AS audiodb` (see openDatabases()). This keeps every
// existing query that joins verses with audio_files/word_timings working
// as a normal SQL join (just qualified with the "audiodb." schema prefix)
// instead of needing separate connections + a manual two-step lookup in
// C++ for every such query.
#pragma once

#include <QObject>
#include <QVariantMap>
#include <QVariantList>
#include <QSqlDatabase>
#include <QSettings>

class QuranBackend : public QObject
{
    Q_OBJECT
public:
    explicit QuranBackend(QObject *parent = nullptr);
    ~QuranBackend();

    // Paths are fixed on the target OS image, e.g.
    // /opt/roohaniye/data/quran_text.db, /opt/roohaniye/data/quran_audio.db.
    // quranAudioDbPath is ATTACHed onto the same connection as
    // quranTextDbPath (schema alias "audiodb") - see class comment above.
    Q_INVOKABLE bool openDatabases(const QString &quranTextDbPath,
                                    const QString &quranAudioDbPath,
                                    const QString &hadithDbPath);

    // ---- Database Connector hooks (see dbconnectorbackend.h) ----
    // Hot-swaps the ATTACHed audio db (DETACH + re-ATTACH on the existing
    // connection) to a user-imported file. Verifies it actually has an
    // audio_files table before committing; leaves the previous attachment
    // detached (not restored) on failure - caller should treat a false
    // return as "audio playback is unavailable until fixed". Persists the
    // choice so it's used again on the next launch too.
    Q_INVOKABLE bool reattachAudioDb(const QString &newPath);
    // Closes and reopens the separate hadith connection against a new
    // file. Verifies a hadiths table exists before committing. Persists
    // the choice for next launch.
    Q_INVOKABLE bool reattachHadithDb(const QString &newPath);

    Q_INVOKABLE QVariantMap verse(int surah, int ayah) const;
    // surahList: id, ayahCount (from db) + nameEnglish, nameArabic, nameTransliteration,
    // revelationPlace ("Meccan"/"Medinan") from the static table below.
    Q_INVOKABLE QVariantList surahList() const;
    Q_INVOKABLE QVariantMap surahInfo(int surah) const;
    // Returns raw mp3 bytes as base64 for the given verse+reciter (QML plays via a temp file or QAudioDecoder)
    Q_INVOKABLE QString audioBase64(int surah, int ayah, const QString &reciterId) const;
    // Writes the verse's audio blob to a cache file on disk (dedup'd by
    // surah/ayah/reciter) and returns the local path, for AudioBackend to
    // hand to QMediaPlayer directly instead of round-tripping base64.
    Q_INVOKABLE QString audioFilePath(int surah, int ayah, const QString &reciterId) const;
    // Available reciters actually present in audio_files, with display
    // name + recitation style (Murattal = measured/steady recitation,
    // Mujawwad = melodic/ornamented) so the UI can label them properly.
    Q_INVOKABLE QVariantList reciterList() const;

    // Expands a multi-select of juz(s)/surah(s)/individual ayah(s) into an
    // ordered, de-duplicated list of {surah,ayah} maps in natural Quran
    // order. Each item in `items` is a map: {"type":"surah","surah":N},
    // {"type":"juz","juz":N}, or {"type":"ayah","surah":N,"ayah":M}. Used
    // by the "select items, then pick a reciter" playback feature (the
    // selection is turned into a playlist for AudioBackend::playSelection).
    Q_INVOKABLE QVariantList versesForSelection(const QVariantList &items) const;

    Q_INVOKABLE QVariantMap randomHadith() const;
    // Picks a uniformly random ayah across the whole Quran (for the
    // Quran view's "Random" tile).
    Q_INVOKABLE QVariantMap randomVerse() const;

    // ---- Hadith reader (mirrors the Quran reader's shape, adapted for
    // hadith's book/topic structure instead of surah/juz - see
    // HadithMenu.qml/HadithTopicPicker.qml/HadithView.qml) ----
    // Books actually present in the db: [{book, displayName, count}].
    Q_INVOKABLE QVariantList hadithBookList() const;
    // Distinct topics within a book, in original chapter order (by
    // MIN(id) per topic, not alphabetical) with a count each:
    // [{topic, count}].
    Q_INVOKABLE QVariantList hadithTopics(const QString &book) const;
    // All hadiths in one topic of one book, ordered by id - bounded (a
    // topic is at most a few dozen hadiths), unlike hadithsInBook below.
    Q_INVOKABLE QVariantList hadithsByTopic(const QString &book, const QString &topic) const;
    // Keyset-paginated continuous browse of a whole book: hadiths with
    // id > afterId (pass 0 for the start of the book, or a saved
    // progress id to resume mid-book), ordered by id, capped at limit.
    // Call again with the last returned id as the new afterId to load
    // the next batch (infinite scroll). Note: forward-only: there is no
    // "load earlier" - resuming from a saved id starts the continuous
    // scroll there and only goes forward, not backward.
    Q_INVOKABLE QVariantList hadithsInBook(const QString &book, int afterId, int limit) const;
    Q_INVOKABLE QVariantMap hadithById(int id) const;
    // FTS5 full-text search across english/urdu/arabic. Query is
    // tokenized and each token is quoted+prefix-matched internally, so
    // arbitrary user input (quotes, FTS operators, etc.) can't produce a
    // malformed MATCH query.
    Q_INVOKABLE QVariantList searchHadiths(const QString &query, int limit) const;
    // Expands a multi-select of topics/individual hadiths into an
    // ordered, de-duplicated list of full hadith maps (by id). Each item
    // is {"type":"topic","book":...,"topic":...} or
    // {"type":"hadith","id":N}. Used by the "select topics/hadiths, then
    // read just those" feature - the hadith equivalent of
    // versesForSelection(), minus a playback step since there's no
    // recitation audio for hadith in this db.
    Q_INVOKABLE QVariantList hadithsForSelection(const QVariantList &items) const;

    // ---- Hadith reading progress (separate from Quran's saveProgress/
    // lastProgress above - keyed by hadith id, not surah/ayah) ----
    Q_INVOKABLE void saveHadithProgress(int id);
    // Returns {} if nothing saved yet, otherwise the full hadith row at
    // the saved id (so the "Continue reading" card can show book/topic/
    // hadith_num without a second lookup).
    Q_INVOKABLE QVariantMap lastHadithProgress() const;

    // ---- Reader navigation helpers (juz/page/manzil/ruku browsing) ----
    Q_INVOKABLE QVariantList versesInSurah(int surah) const;
    Q_INVOKABLE QVariantList versesInJuz(int juz) const;
    Q_INVOKABLE QVariantList versesInPage(int page) const;
    Q_INVOKABLE QVariantList versesInManzil(int manzil) const;
    Q_INVOKABLE QVariantList versesInRuku(int ruku) const;
    Q_INVOKABLE int totalJuz() const { return 30; }
    Q_INVOKABLE int totalPages() const;
    Q_INVOKABLE int totalManzils() const { return 7; }
    Q_INVOKABLE int totalRukus() const;
    // Stats for the "About Quran" panel: surahs, ayahs, juz, pages,
    // manzils, rukus, hizbQuarters, sajdas (counts pulled live from db).
    Q_INVOKABLE QVariantMap quranStats() const;

    // Sequential navigation helpers for continuous/loop playback -
    // wraps at the end of the Quran back to 1:1.
    Q_INVOKABLE QVariantMap nextVerse(int surah, int ayah) const;
    Q_INVOKABLE QVariantMap previousVerse(int surah, int ayah) const;

    // ---- Reading progress + preferences (QSettings-backed, persists across runs) ----
    Q_INVOKABLE void saveProgress(int surah, int ayah);
    Q_INVOKABLE QVariantMap lastProgress() const;
    Q_INVOKABLE void setPreference(const QString &key, const QVariant &value);
    Q_INVOKABLE QVariant preference(const QString &key, const QVariant &defaultValue) const;

private:
    QVariantMap rowToVerseMap(class QSqlQuery &q) const;
    QVariantMap rowToHadithMap(class QSqlQuery &q) const;

    QSqlDatabase m_quranDb;
    QSqlDatabase m_hadithDb;
    // True once "audiodb" is actually ATTACHed on m_quranDb - false for
    // the lite ISO variant before an audio DB import, or if attach
    // failed. Every audiodb.-qualified query must check this first and
    // return an empty/graceful result rather than issue a query against
    // a schema that was never attached (which would still just fail per-
    // call, not crash, but there's no reason to pay for a doomed round
    // trip to SQLite when we already know the answer).
    bool m_audioDbAttached = false;
    mutable QSettings m_settings;
};
