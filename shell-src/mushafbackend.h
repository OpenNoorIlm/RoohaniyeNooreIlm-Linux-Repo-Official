// MushafBackend: read-only layer over mushafs.db, a single SQLite file
// containing full-page scanned mushaf images (8 different printed/hafizi
// mushaf editions) as PNG BLOBs.
//
// Schema (see scripts used to build it, ~/Downloads/quran/build_mushafs_db.py):
//   pages(id INTEGER PRIMARY KEY, mushaf_name TEXT, page_number INTEGER,
//         format TEXT, image BLOB), indexed on (mushaf_name, page_number).
//
// Like QuranBackend::audioFilePath(), page images are never handed to QML
// as base64 - each requested page is written once to a disk cache file
// (dedup'd by mushaf+page) and the local file:// path is returned, so an
// Image {} element can load it directly instead of round-tripping a
// multi-MB base64 string through the QML/JS bridge.
#pragma once

#include <QObject>
#include <QVariantMap>
#include <QVariantList>
#include <QSqlDatabase>
#include <QSettings>

class MushafBackend : public QObject
{
    Q_OBJECT
public:
    explicit MushafBackend(QObject *parent = nullptr);
    ~MushafBackend();

    // Path is fixed on the target OS image: /opt/roohaniye/data/mushafs.db.
    Q_INVOKABLE bool openDatabase(const QString &dbPath);

    // All mushaf editions present in the db: [{mushafName, displayName,
    // pageCount, minPage, maxPage}], ordered by displayName. displayName
    // is derived from the raw folder-name-style mushafName (see .cpp).
    Q_INVOKABLE QVariantList mushafList() const;

    // Writes the requested page's PNG blob to a cache file on disk
    // (dedup'd by mushaf+page, so repeat visits are instant) and returns
    // the local path for QML's Image{} to load via "file://" + path.
    // Returns empty string if the page doesn't exist / db not open.
    Q_INVOKABLE QString pageImagePath(const QString &mushafName, int pageNumber) const;

    Q_INVOKABLE int pageCount(const QString &mushafName) const;
    Q_INVOKABLE int minPage(const QString &mushafName) const;
    Q_INVOKABLE int maxPage(const QString &mushafName) const;

    // ---- Reading progress + last-picked mushaf (QSettings-backed,
    // persists across runs - separate settings keys from QuranBackend's
    // progress, since mushaf reading position is independent of the
    // surah/ayah-based Quran reader progress). ----
    Q_INVOKABLE void saveProgress(const QString &mushafName, int pageNumber);
    // Returns {} if nothing saved yet, otherwise {mushafName, pageNumber}.
    Q_INVOKABLE QVariantMap lastProgress() const;

private:
    QSqlDatabase m_db;
    mutable QSettings m_settings;
};
