#include "storagebackend.h"

#include <QDir>
#include <QFileInfo>
#include <QStorageInfo>
#include <QSet>
#include <QProcessEnvironment>

StorageBackend::StorageBackend(QObject *parent) : QObject(parent)
{
    connect(&m_pollTimer, &QTimer::timeout, this, &StorageBackend::refresh);
    m_pollTimer.start(2000); // 2s poll - cheap directory listing, fine at this interval
    refresh();
}

void StorageBackend::refresh()
{
    QVariantList found;
    QSet<QString> foundPaths;

    const QString user = QProcessEnvironment::systemEnvironment().value("USER");
    QStringList roots = {
        "/media/" + user,
        "/run/media/" + user,
        "/media"
    };

    for (const QString &root : roots) {
        QDir dir(root);
        if (!dir.exists()) continue;

        const auto entries = dir.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot);
        for (const QFileInfo &fi : entries) {
            const QString mountPath = fi.absoluteFilePath();
            if (foundPaths.contains(mountPath)) continue;

            // Only count it if it's genuinely a separate mounted filesystem
            // (a removable drive's mount point is always its own root), not
            // just an empty directory sitting under /media.
            QStorageInfo si(mountPath);
            if (!si.isValid() || si.rootPath() != mountPath) continue;

            foundPaths.insert(mountPath);
            QVariantMap dev;
            dev["label"] = fi.fileName();
            dev["path"] = mountPath;
            found.append(dev);
        }
    }

    QSet<QString> oldPaths;
    for (const QVariant &v : m_devices) oldPaths.insert(v.toMap().value("path").toString());

    for (const QVariant &v : found) {
        const QString p = v.toMap().value("path").toString();
        if (!oldPaths.contains(p)) emit deviceAdded(p, v.toMap().value("label").toString());
    }
    for (const QString &p : oldPaths) {
        if (!foundPaths.contains(p)) emit deviceRemoved(p);
    }

    if (found != m_devices) {
        m_devices = found;
        emit devicesChanged();
    }
}
