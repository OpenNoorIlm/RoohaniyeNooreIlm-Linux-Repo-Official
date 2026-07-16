// ThemeBackend: light/dark mode, accent color, and a custom background
// image, all persisted to the same shell_settings.ini every other
// backend uses. The background image itself is copied into
// /opt/roohaniye/data/backgrounds/ (not referenced in place) so it
// survives the source USB/SD card being removed - same "import, don't
// just point at removable media" philosophy as DbConnectorBackend.
#pragma once

#include <QObject>
#include <QString>
#include <QSettings>
#include <QVariantMap>

class ThemeBackend : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool darkMode READ darkMode NOTIFY darkModeChanged)
    Q_PROPERTY(QString accentColor READ accentColor NOTIFY accentColorChanged)
    Q_PROPERTY(QString backgroundImage READ backgroundImage NOTIFY backgroundImageChanged) // file:// url, "" = none
    Q_PROPERTY(qreal backgroundOpacity READ backgroundOpacity NOTIFY backgroundOpacityChanged) // 0.0-1.0, how strongly the image shows through screen content

public:
    explicit ThemeBackend(QObject *parent = nullptr);

    bool darkMode() const { return m_darkMode; }
    QString accentColor() const { return m_accentColor; }
    QString backgroundImage() const { return m_backgroundImage; }
    qreal backgroundOpacity() const { return m_backgroundOpacity; }

    Q_INVOKABLE void setDarkMode(bool on);
    Q_INVOKABLE void setAccentColor(const QString &hexColor);
    // Copies srcPath into /opt/roohaniye/data/backgrounds/, validates
    // it's a real image Qt can load, and sets it as the active
    // background. Returns { ok: bool, error: string }.
    Q_INVOKABLE QVariantMap setBackgroundImage(const QString &srcPath);
    Q_INVOKABLE void clearBackgroundImage();
    Q_INVOKABLE void setBackgroundOpacity(qreal opacity);

signals:
    void darkModeChanged();
    void accentColorChanged();
    void backgroundImageChanged();
    void backgroundOpacityChanged();

private:
    void load();
    QSettings m_settings;
    bool m_darkMode = true;          // dark is the app's original/default look
    QString m_accentColor = "#7fd6b4";
    QString m_backgroundImage = "";
    qreal m_backgroundOpacity = 0.18;
};
