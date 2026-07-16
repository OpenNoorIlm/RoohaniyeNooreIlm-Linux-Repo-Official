#include "mushafbackend.h"

#include <QSqlQuery>
#include <QSqlError>
#include <QVariant>
#include <QDebug>
#include <QFile>
#include <QDir>
#include <QStandardPaths>
#include <QRegExp>
#include <QStringList>
#include <algorithm>

namespace {

// Raw mushafName values are folder names from the scan source, shaped
// like "hafizi_<region>_<variant>__<OriginalTitle>" or a bare name like
// "indo-pak". Turn them into something presentable without needing a
// hand-maintained lookup table per entry (there are 8 now, could grow).
QString prettifyMushafName(const QString &raw)
{
    QString name = raw;
    // Drop everything from the "__<OriginalTitle>" suffix onward - the
    // prefix before it is already a readable region/variant label.
    const int sep = name.indexOf("__");
    if (sep >= 0) name = name.left(sep);
    name.replace('_', ' ');
    name.replace('-', ' ');
    // Title-case each word.
    QStringList words = name.split(' ', Qt::SkipEmptyParts);
    for (QString &w : words) {
        if (w.isEmpty()) continue;
        w[0] = w[0].toUpper();
    }
    return words.join(' ');
}

} // namespace

MushafBackend::MushafBackend(QObject *parent)
    : QObject(parent)
    , m_settings(QStringLiteral("/opt/roohaniye/data/shell_settings.ini"), QSettings::IniFormat)
{
}

MushafBackend::~MushafBackend()
{
    if (m_db.isOpen()) m_db.close();
}

bool MushafBackend::openDatabase(const QString &dbPath)
{
    if (!QFile::exists(dbPath)) {
        qWarning() << "MushafBackend: db not found at" << dbPath;
        return false;
    }

    m_db = QSqlDatabase::addDatabase("QSQLITE", "mushaf_conn");
    m_db.setDatabaseName(dbPath);
    // Read-only: this shell never writes to the scripture DBs.
    m_db.setConnectOptions("QSQLITE_OPEN_READONLY");
    const bool ok = m_db.open();
    if (!ok) {
        qWarning() << "MushafBackend: failed to open db:" << m_db.lastError().text();
    }
    qDebug() << "MushafBackend::openDatabase: ok=" << ok;
    return ok;
}

QVariantList MushafBackend::mushafList() const
{
    QVariantList out;
    if (!m_db.isOpen()) return out;

    QSqlQuery q(m_db);
    if (!q.exec("SELECT mushaf_name, COUNT(*), MIN(page_number), MAX(page_number) "
                "FROM pages GROUP BY mushaf_name")) {
        qWarning() << "mushafList failed:" << q.lastError().text();
        return out;
    }

    QList<QVariantMap> rows;
    while (q.next()) {
        QVariantMap m;
        const QString raw = q.value(0).toString();
        m["mushafName"] = raw;
        m["displayName"] = prettifyMushafName(raw);
        m["pageCount"] = q.value(1).toInt();
        m["minPage"] = q.value(2).toInt();
        m["maxPage"] = q.value(3).toInt();
        rows.append(m);
    }
    std::sort(rows.begin(), rows.end(), [](const QVariantMap &a, const QVariantMap &b) {
        return a["displayName"].toString() < b["displayName"].toString();
    });
    for (const auto &m : rows) out.append(m);
    return out;
}

QString MushafBackend::pageImagePath(const QString &mushafName, int pageNumber) const
{
    if (!m_db.isOpen()) {
        qWarning() << "pageImagePath: db not open";
        return {};
    }

    const QString cacheDir = QStandardPaths::writableLocation(QStandardPaths::CacheLocation)
                              + "/roohaniye-mushaf";
    QDir().mkpath(cacheDir);

    // mushafName can contain characters that are awkward in a filename
    // (spaces, dashes are fine, but be defensive) - sanitize the same
    // way QuranBackend::audioFilePath() sanitizes reciterId.
    QString safeName = mushafName;
    safeName.replace(QRegExp("[^A-Za-z0-9_.-]"), "_");

    const QString path = QString("%1/%2_p%3.png").arg(cacheDir).arg(safeName).arg(pageNumber);
    if (QFile::exists(path)) return path;

    QSqlQuery q(m_db);
    q.prepare("SELECT image FROM pages WHERE mushaf_name = ? AND page_number = ? LIMIT 1");
    q.addBindValue(mushafName);
    q.addBindValue(pageNumber);
    if (!q.exec() || !q.next()) {
        qWarning() << "pageImagePath: no page for" << mushafName << pageNumber;
        return {};
    }

    QFile f(path);
    if (!f.open(QIODevice::WriteOnly)) {
        qWarning() << "pageImagePath: failed to write cache file" << path;
        return {};
    }
    f.write(q.value(0).toByteArray());
    f.close();
    return path;
}

int MushafBackend::pageCount(const QString &mushafName) const
{
    if (!m_db.isOpen()) return 0;
    QSqlQuery q(m_db);
    q.prepare("SELECT COUNT(*) FROM pages WHERE mushaf_name = ?");
    q.addBindValue(mushafName);
    if (q.exec() && q.next()) return q.value(0).toInt();
    return 0;
}

int MushafBackend::minPage(const QString &mushafName) const
{
    if (!m_db.isOpen()) return 0;
    QSqlQuery q(m_db);
    q.prepare("SELECT MIN(page_number) FROM pages WHERE mushaf_name = ?");
    q.addBindValue(mushafName);
    if (q.exec() && q.next()) return q.value(0).toInt();
    return 0;
}

int MushafBackend::maxPage(const QString &mushafName) const
{
    if (!m_db.isOpen()) return 0;
    QSqlQuery q(m_db);
    q.prepare("SELECT MAX(page_number) FROM pages WHERE mushaf_name = ?");
    q.addBindValue(mushafName);
    if (q.exec() && q.next()) return q.value(0).toInt();
    return 0;
}

void MushafBackend::saveProgress(const QString &mushafName, int pageNumber)
{
    m_settings.setValue("mushafProgress/mushafName", mushafName);
    m_settings.setValue("mushafProgress/pageNumber", pageNumber);
    m_settings.sync();
}

QVariantMap MushafBackend::lastProgress() const
{
    QVariantMap m;
    const QString name = m_settings.value("mushafProgress/mushafName", "").toString();
    if (name.isEmpty()) return m;
    m["mushafName"] = name;
    m["pageNumber"] = m_settings.value("mushafProgress/pageNumber", 1).toInt();
    return m;
}
