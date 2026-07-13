// DbConnectorBackend: the "Database Connector" app. Lets the user browse a
// mounted USB/SD card (via StorageBackend), pick a .db file - or a folder
// or .json file to be converted into one - imports it into
// /opt/roohaniye/data/imported/, inspects its SQLite schema, and reports
// which of this OS's built-in apps that schema matches, so the user can
// one-tap "connect" an external database in place of the bundled one.
// e.g.: insert a USB stick with a quran_audio.db-shaped file on it, open
// this app, pick the file, it shows "Quran Audio (Recitations)" as a
// match, tap it, done.
//
// Schema matching is a small static registry (required table + required
// columns), not anything fuzzy - see SIGNATURES in the .cpp.
//
// Live hot-swap (no shell restart needed) is supported for quran_audio
// (it's ATTACHed as a secondary schema on QuranBackend's connection, so
// swapping it is just DETACH/re-ATTACH) and hadith_db (its own
// QSqlDatabase connection - close/reopen). Swapping the main
// quran_text.db live is NOT supported yet - it's the base connection
// everything else is ATTACHed onto, so swapping it would mean closing and
// reopening the whole connection including the audio attachment. Import
// still works for it, it just requires a shell restart to take effect,
// which connectToApp() reports back via the "requiresRestart" field.
#pragma once

#include <QObject>
#include <QVariantList>
#include <QVariantMap>

class QuranBackend;

class DbConnectorBackend : public QObject
{
    Q_OBJECT
public:
    explicit DbConnectorBackend(QuranBackend *quranBackend, QObject *parent = nullptr);

    // Lists dirs/files at `path` (name, path, isDir, isDb, isJson,
    // sizeLabel), sorted directories-first then by name. Empty path lists
    // /media (the browser's QML side is expected to start at a detected
    // storage device's own path instead, from StorageBackend.devices).
    Q_INVOKABLE QVariantList listDirectory(const QString &path) const;

    // Takes a selected file OR folder path from the browser. If it's a
    // .db/.sqlite/.sqlite3 file, copies it into the imports dir as-is. If
    // it's a folder, looks inside (this folder, then one level of
    // subfolders) for a .db file first, falling back to converting a
    // .json file found the same way. A bare .json path is converted
    // directly. Either way, the resulting db's schema is introspected and
    // matched against known app signatures.
    // Returns: { ok, error, importedPath, matchedApps: [ { id, name,
    //   tableMatched } ] }
    Q_INVOKABLE QVariantMap importPath(const QString &path);

    // Connects an already-imported db (importedPath, from importPath's
    // result) to the given matched app id ("quran_audio", "quran_text",
    // "hadith_db"). Returns { ok, error, requiresRestart }.
    Q_INVOKABLE QVariantMap connectToApp(const QString &importedPath, const QString &appId);

private:
    QString importsDir() const;
    // Returns {} on failure with `error` set; else { path: <new db path> }.
    QVariantMap convertJsonToDb(const QString &jsonPath, QString &error) const;
    // Empty string if nothing found.
    QString findDbInFolder(const QString &folderPath) const;
    // Empty string if nothing found (falls back to convertJsonToDb by the caller).
    QString findJsonInFolder(const QString &folderPath) const;
    QVariantList matchSchema(const QString &dbPath) const;

    QuranBackend *m_quranBackend;
};
