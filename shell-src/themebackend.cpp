#include "themebackend.h"
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QImageReader>
#include <QUrl>

ThemeBackend::ThemeBackend(QObject *parent)
    : QObject(parent)
    , m_settings(QStringLiteral("/opt/roohaniye/data/shell_settings.ini"), QSettings::IniFormat)
{
    load();
}

void ThemeBackend::load()
{
    m_settings.beginGroup("theme");
    m_darkMode = m_settings.value("darkMode", true).toBool();
    m_accentColor = m_settings.value("accentColor", "#7fd6b4").toString();
    m_backgroundImage = m_settings.value("backgroundImage", "").toString();
    m_backgroundOpacity = m_settings.value("backgroundOpacity", 0.18).toDouble();
    m_settings.endGroup();

    // If a previously-saved background file got deleted out from under
    // us (e.g. manual cleanup of /opt/roohaniye/data), fall back to no
    // background rather than pointing QML at a dead file:// url.
    if (!m_backgroundImage.isEmpty()) {
        QString localPath = QUrl(m_backgroundImage).toLocalFile();
        if (localPath.isEmpty() || !QFile::exists(localPath)) {
            m_backgroundImage = "";
        }
    }
}

void ThemeBackend::setDarkMode(bool on)
{
    if (m_darkMode == on) return;
    m_darkMode = on;
    m_settings.setValue("theme/darkMode", on);
    m_settings.sync();
    emit darkModeChanged();
}

void ThemeBackend::setAccentColor(const QString &hexColor)
{
    if (hexColor.isEmpty() || hexColor == m_accentColor) return;
    m_accentColor = hexColor;
    m_settings.setValue("theme/accentColor", hexColor);
    m_settings.sync();
    emit accentColorChanged();
}

QVariantMap ThemeBackend::setBackgroundImage(const QString &srcPath)
{
    QVariantMap result;

    QString localSrc = srcPath.startsWith("file://") ? QUrl(srcPath).toLocalFile() : srcPath;
    QFileInfo info(localSrc);
    if (!info.exists() || !info.isFile()) {
        result["ok"] = false;
        result["error"] = "File not found.";
        return result;
    }

    // Validate it's actually a decodable image before committing to it -
    // same "don't trust the extension" caution as DbConnectorBackend
    // uses for .db/.json imports.
    QImageReader reader(localSrc);
    if (!reader.canRead()) {
        result["ok"] = false;
        result["error"] = "That file isn't a readable image (tried: " + reader.errorString() + ").";
        return result;
    }

    QDir dataDir("/opt/roohaniye/data/backgrounds");
    if (!dataDir.exists() && !dataDir.mkpath(".")) {
        result["ok"] = false;
        result["error"] = "Couldn't create backgrounds folder.";
        return result;
    }

    // Fixed destination filename (not the original name) so repeated
    // imports don't slowly fill the disk with old backgrounds - there's
    // only ever one active custom background at a time.
    QString ext = info.suffix().isEmpty() ? "img" : info.suffix();
    QString destPath = dataDir.filePath("background." + ext);

    // Clean up any previous background file(s) with a different
    // extension before copying the new one in.
    for (const QString &old : dataDir.entryList(QStringList() << "background.*", QDir::Files)) {
        dataDir.remove(old);
    }

    if (!QFile::copy(localSrc, destPath)) {
        result["ok"] = false;
        result["error"] = "Couldn't copy the image into place.";
        return result;
    }

    m_backgroundImage = QUrl::fromLocalFile(destPath).toString();
    m_settings.setValue("theme/backgroundImage", m_backgroundImage);
    m_settings.sync();
    emit backgroundImageChanged();

    result["ok"] = true;
    result["error"] = "";
    return result;
}

void ThemeBackend::clearBackgroundImage()
{
    if (m_backgroundImage.isEmpty()) return;
    QDir dataDir("/opt/roohaniye/data/backgrounds");
    if (dataDir.exists()) {
        for (const QString &f : dataDir.entryList(QStringList() << "background.*", QDir::Files)) {
            dataDir.remove(f);
        }
    }
    m_backgroundImage = "";
    m_settings.setValue("theme/backgroundImage", "");
    m_settings.sync();
    emit backgroundImageChanged();
}

void ThemeBackend::setBackgroundOpacity(qreal opacity)
{
    qreal clamped = qBound(0.0, opacity, 1.0);
    if (qFuzzyCompare(m_backgroundOpacity, clamped)) return;
    m_backgroundOpacity = clamped;
    m_settings.setValue("theme/backgroundOpacity", clamped);
    m_settings.sync();
    emit backgroundOpacityChanged();
}
