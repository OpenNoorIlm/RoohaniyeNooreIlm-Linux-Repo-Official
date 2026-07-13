#include "dbconnectorbackend.h"
#include "quranbackend.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QSqlDatabase>
#include <QSqlQuery>
#include <QSqlError>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QJsonValue>
#include <QMap>
#include <QSet>
#include <QDebug>
#include <QRegularExpression>

namespace {

QString sanitizeIdentifier(const QString &raw)
{
    QString s = raw;
    s.replace(QRegularExpression("[^A-Za-z0-9_]"), "_");
    if (s.isEmpty()) s = "col";
    if (s.at(0).isDigit()) s.prepend("_");
    return s;
}

// One-shot temp connection name generator so repeated imports in the same
// process don't collide on QSqlDatabase's global connection-name registry.
QString tempConnName(const QString &prefix)
{
    static int counter = 0;
    return QString("%1_%2").arg(prefix).arg(++counter);
}

struct AppSignature {
    const char *appId;
    const char *appName;
    const char *table;
    QStringList requiredCols;
};

const QList<AppSignature> &appSignatures()
{
    static const QList<AppSignature> sigs = {
        { "quran_audio", "Quran Audio (Recitations)", "audio_files", {"verse_id", "reciter_id", "audio_data"} },
        { "quran_text",  "Quran Text (Verses)",       "verses",      {"surah", "ayah", "text_uthmani"} },
        { "hadith_db",   "Hadith Collection",         "hadiths",     {"book", "hadith_num", "english"} },
    };
    return sigs;
}

} // namespace

DbConnectorBackend::DbConnectorBackend(QuranBackend *quranBackend, QObject *parent)
    : QObject(parent), m_quranBackend(quranBackend)
{
}

QString DbConnectorBackend::importsDir() const
{
    return "/opt/roohaniye/data/imported";
}

QVariantList DbConnectorBackend::listDirectory(const QString &path) const
{
    QVariantList result;
    QString target = path.isEmpty() ? QStringLiteral("/media") : path;

    QDir dir(target);
    if (!dir.exists()) return result;

    const QFileInfoList entries = dir.entryInfoList(
        QDir::Dirs | QDir::Files | QDir::NoDotAndDotDot,
        QDir::DirsFirst | QDir::Name);

    for (const QFileInfo &fi : entries) {
        QVariantMap item;
        item["name"] = fi.fileName();
        item["path"] = fi.absoluteFilePath();
        item["isDir"] = fi.isDir();
        const QString suf = fi.suffix().toLower();
        item["isDb"] = !fi.isDir() && (suf == "db" || suf == "sqlite" || suf == "sqlite3");
        item["isJson"] = !fi.isDir() && suf == "json";

        if (!fi.isDir()) {
            const qint64 bytes = fi.size();
            if (bytes < 1024 * 1024)
                item["sizeLabel"] = QString("%1 KB").arg(bytes / 1024);
            else if (bytes < 1024LL * 1024 * 1024)
                item["sizeLabel"] = QString::number(bytes / (1024.0 * 1024.0), 'f', 1) + " MB";
            else
                item["sizeLabel"] = QString::number(bytes / (1024.0 * 1024.0 * 1024.0), 'f', 2) + " GB";
        } else {
            item["sizeLabel"] = "";
        }
        result.append(item);
    }
    return result;
}

QString DbConnectorBackend::findDbInFolder(const QString &folderPath) const
{
    QDir dir(folderPath);
    const QStringList direct = dir.entryList(QStringList() << "*.db" << "*.sqlite" << "*.sqlite3",
                                              QDir::Files, QDir::Name);
    if (!direct.isEmpty()) return dir.filePath(direct.first());

    // One level of subfolders only - keeps this bounded on a large drive.
    const auto subdirs = dir.entryList(QDir::Dirs | QDir::NoDotAndDotDot);
    for (const QString &sd : subdirs) {
        QDir sub(dir.filePath(sd));
        const QStringList found = sub.entryList(QStringList() << "*.db" << "*.sqlite" << "*.sqlite3",
                                                 QDir::Files, QDir::Name);
        if (!found.isEmpty()) return sub.filePath(found.first());
    }
    return QString();
}

QString DbConnectorBackend::findJsonInFolder(const QString &folderPath) const
{
    QDir dir(folderPath);
    const QStringList direct = dir.entryList(QStringList() << "*.json", QDir::Files, QDir::Name);
    if (!direct.isEmpty()) return dir.filePath(direct.first());

    const auto subdirs = dir.entryList(QDir::Dirs | QDir::NoDotAndDotDot);
    for (const QString &sd : subdirs) {
        QDir sub(dir.filePath(sd));
        const QStringList found = sub.entryList(QStringList() << "*.json", QDir::Files, QDir::Name);
        if (!found.isEmpty()) return sub.filePath(found.first());
    }
    return QString();
}

QVariantMap DbConnectorBackend::convertJsonToDb(const QString &jsonPath, QString &error) const
{
    QFile f(jsonPath);
    if (!f.open(QIODevice::ReadOnly)) {
        error = "Could not open JSON file";
        return {};
    }
    QJsonParseError perr;
    QJsonDocument doc = QJsonDocument::fromJson(f.readAll(), &perr);
    f.close();
    if (perr.error != QJsonParseError::NoError) {
        error = "Invalid JSON: " + perr.errorString();
        return {};
    }

    QDir().mkpath(importsDir());
    const QString outPath = importsDir() + "/" + QFileInfo(jsonPath).completeBaseName() + "_converted.db";
    QFile::remove(outPath);

    const QString connName = tempConnName("json_convert");
    QSqlDatabase db = QSqlDatabase::addDatabase("QSQLITE", connName);
    db.setDatabaseName(outPath);
    if (!db.open()) {
        error = "Could not create output database: " + db.lastError().text();
        db = QSqlDatabase(); // drop this function's reference before removeDatabase()
        QSqlDatabase::removeDatabase(connName);
        return {};
    }

    // Collect {tableName -> array of flat objects}. Supports: a bare
    // top-level array (-> single table "data"), or an object whose values
    // are arrays-of-objects (-> one table per key, other keys ignored).
    // Falls back to treating the whole object as a single one-row table
    // if neither shape matches - good enough for arbitrary simple JSON,
    // not a general nested-schema importer.
    QMap<QString, QJsonArray> tables;
    if (doc.isArray()) {
        tables["data"] = doc.array();
    } else if (doc.isObject()) {
        const QJsonObject obj = doc.object();
        for (auto it = obj.begin(); it != obj.end(); ++it) {
            if (it.value().isArray()) {
                const QJsonArray arr = it.value().toArray();
                if (!arr.isEmpty() && arr.first().isObject())
                    tables[it.key()] = arr;
            }
        }
        if (tables.isEmpty()) {
            QJsonArray single;
            single.append(obj);
            tables["data"] = single;
        }
    } else {
        error = "JSON top level must be an object or array";
        db.close();
        db = QSqlDatabase();
        QSqlDatabase::removeDatabase(connName);
        return {};
    }

    bool anyTableCreated = false;
    for (auto it = tables.begin(); it != tables.end(); ++it) {
        const QString tableName = sanitizeIdentifier(it.key());
        const QJsonArray &rows = it.value();
        if (rows.isEmpty()) continue;

        QStringList cols;
        QSet<QString> colSet;
        for (const QJsonValue &rv : rows) {
            if (!rv.isObject()) continue;
            const QJsonObject o = rv.toObject();
            for (auto keyIt = o.constBegin(); keyIt != o.constEnd(); ++keyIt) {
                const QString col = sanitizeIdentifier(keyIt.key());
                if (!colSet.contains(col)) { colSet.insert(col); cols.append(col); }
            }
        }
        if (cols.isEmpty()) continue;

        QStringList colDefs;
        for (const QString &c : cols) colDefs << QString("\"%1\" TEXT").arg(c);
        QSqlQuery createQ(db);
        if (!createQ.exec(QString("CREATE TABLE \"%1\" (%2)").arg(tableName, colDefs.join(", ")))) {
            qWarning() << "convertJsonToDb: CREATE TABLE failed for" << tableName << createQ.lastError().text();
            continue;
        }

        QStringList quotedCols;
        QStringList placeholders;
        for (const QString &c : cols) { quotedCols << QString("\"%1\"").arg(c); placeholders << "?"; }
        const QString insertSql = QString("INSERT INTO \"%1\" (%2) VALUES (%3)")
            .arg(tableName, quotedCols.join(", "), placeholders.join(", "));

        db.transaction();
        QSqlQuery ins(db);
        ins.prepare(insertSql);
        // cols is sanitized; keep the original (pre-sanitize) key per
        // position so we can still look values up in each row's object.
        QStringList originalKeysInOrder;
        {
            QSet<QString> seen;
            for (const QJsonValue &rv : rows) {
                if (!rv.isObject()) continue;
                const QJsonObject o = rv.toObject();
                for (auto keyIt = o.constBegin(); keyIt != o.constEnd(); ++keyIt) {
                    const QString sanitized = sanitizeIdentifier(keyIt.key());
                    if (cols.contains(sanitized) && !seen.contains(sanitized)) {
                        seen.insert(sanitized);
                        originalKeysInOrder.append(keyIt.key());
                    }
                }
            }
        }
        for (const QJsonValue &rv : rows) {
            const QJsonObject o = rv.toObject();
            for (const QString &c : cols) {
                // Find original key mapping to this sanitized column.
                QString origKey = c;
                for (const QString &ok : originalKeysInOrder) {
                    if (sanitizeIdentifier(ok) == c) { origKey = ok; break; }
                }
                const QJsonValue v = o.value(origKey);
                if (v.isString()) ins.addBindValue(v.toString());
                else if (v.isDouble()) ins.addBindValue(v.toDouble());
                else if (v.isBool()) ins.addBindValue(v.toBool() ? 1 : 0);
                else if (v.isArray()) ins.addBindValue(QString::fromUtf8(QJsonDocument(v.toArray()).toJson(QJsonDocument::Compact)));
                else if (v.isObject()) ins.addBindValue(QString::fromUtf8(QJsonDocument(v.toObject()).toJson(QJsonDocument::Compact)));
                else ins.addBindValue(QVariant());
            }
            if (!ins.exec()) {
                qWarning() << "convertJsonToDb: insert failed:" << ins.lastError().text();
            }
        }
        db.commit();
        anyTableCreated = true;
    }

    db.close();
    db = QSqlDatabase();
    QSqlDatabase::removeDatabase(connName);

    if (!anyTableCreated) {
        error = "No usable table data found in JSON";
        QFile::remove(outPath);
        return {};
    }

    QVariantMap result;
    result["path"] = outPath;
    return result;
}

QVariantList DbConnectorBackend::matchSchema(const QString &dbPath) const
{
    QVariantList matches;
    const QString connName = tempConnName("schema_check");
    QSqlDatabase db = QSqlDatabase::addDatabase("QSQLITE", connName);
    db.setDatabaseName(dbPath);
    db.setConnectOptions("QSQLITE_OPEN_READONLY");
    if (!db.open()) {
        db = QSqlDatabase();
        QSqlDatabase::removeDatabase(connName);
        return matches;
    }

    QSqlQuery tq(db);
    tq.exec("SELECT name FROM sqlite_master WHERE type='table'");
    QStringList tableNames;
    while (tq.next()) tableNames << tq.value(0).toString();

    for (const AppSignature &sig : appSignatures()) {
        // case-insensitive table name match
        QString matchedTable;
        for (const QString &t : tableNames) {
            if (t.compare(sig.table, Qt::CaseInsensitive) == 0) { matchedTable = t; break; }
        }
        if (matchedTable.isEmpty()) continue;

        QSqlQuery cq(db);
        cq.exec(QString("PRAGMA table_info(\"%1\")").arg(matchedTable));
        QStringList cols;
        while (cq.next()) cols << cq.value(1).toString();

        bool allPresent = true;
        for (const QString &rc : sig.requiredCols) {
            bool has = false;
            for (const QString &c : cols) if (c.compare(rc, Qt::CaseInsensitive) == 0) { has = true; break; }
            if (!has) { allPresent = false; break; }
        }
        if (!allPresent) continue;

        QVariantMap m;
        m["id"] = sig.appId;
        m["name"] = sig.appName;
        m["tableMatched"] = matchedTable;
        matches.append(m);
    }

    db.close();
    db = QSqlDatabase();
    QSqlDatabase::removeDatabase(connName);
    return matches;
}

QVariantMap DbConnectorBackend::importPath(const QString &path)
{
    QVariantMap result;
    result["ok"] = false;

    QFileInfo fi(path);
    if (!fi.exists()) {
        result["error"] = "Path does not exist";
        return result;
    }

    QDir().mkpath(importsDir());

    QString sourceDbPath;
    QString error;

    if (fi.isDir()) {
        sourceDbPath = findDbInFolder(path);
        if (sourceDbPath.isEmpty()) {
            const QString jsonPath = findJsonInFolder(path);
            if (jsonPath.isEmpty()) {
                result["error"] = "No .db or .json file found in that folder (checked one level of subfolders)";
                return result;
            }
            QVariantMap conv = convertJsonToDb(jsonPath, error);
            if (conv.isEmpty()) { result["error"] = error; return result; }
            sourceDbPath = conv["path"].toString();
        }
    } else {
        const QString suf = fi.suffix().toLower();
        if (suf == "json") {
            QVariantMap conv = convertJsonToDb(path, error);
            if (conv.isEmpty()) { result["error"] = error; return result; }
            sourceDbPath = conv["path"].toString();
        } else if (suf == "db" || suf == "sqlite" || suf == "sqlite3") {
            const QString dest = importsDir() + "/" + fi.fileName();
            if (QFile::exists(dest)) QFile::remove(dest);
            if (!QFile::copy(path, dest)) {
                result["error"] = "Could not copy database file into " + importsDir();
                return result;
            }
            sourceDbPath = dest;
        } else {
            result["error"] = "Unsupported file type - choose a .db file, a .json file, or a folder containing one";
            return result;
        }
    }

    result["ok"] = true;
    result["importedPath"] = sourceDbPath;
    result["matchedApps"] = matchSchema(sourceDbPath);
    return result;
}

QVariantMap DbConnectorBackend::connectToApp(const QString &importedPath, const QString &appId)
{
    QVariantMap result;
    if (!QFile::exists(importedPath)) {
        result["ok"] = false;
        result["error"] = "Imported file no longer exists";
        return result;
    }

    if (appId == "quran_audio") {
        const bool ok = m_quranBackend->reattachAudioDb(importedPath);
        result["ok"] = ok;
        result["requiresRestart"] = false;
        if (!ok) result["error"] = "Could not attach as the audio database - check its schema";
        return result;
    }
    if (appId == "hadith_db") {
        const bool ok = m_quranBackend->reattachHadithDb(importedPath);
        result["ok"] = ok;
        result["requiresRestart"] = false;
        if (!ok) result["error"] = "Could not open as the hadith database - check its schema";
        return result;
    }
    if (appId == "quran_text") {
        // Base connection - can't be hot-swapped without tearing down the
        // audiodb attachment too. Store the override; picked up on next
        // launch by QuranBackend::openDatabases().
        m_quranBackend->setPreference("quranTextDbOverridePath", importedPath);
        result["ok"] = true;
        result["requiresRestart"] = true;
        return result;
    }

    result["ok"] = false;
    result["error"] = "Unknown app id: " + appId;
    return result;
}
