// RoohaniyeNooreIlmLinux shell
// Entry point: runs as the ONLY GUI process on the machine (eglfs, no X11/Wayland
// compositor needed). Registers C++ backends to QML, then loads Main.qml.

#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QTouchDevice>
#include "appcenter.h"
#include "quranbackend.h"
#include "mushafbackend.h"
#include "audiobackend.h"
#include "wifibackend.h"
#include "powerbackend.h"
#include "storagebackend.h"
#include "dbconnectorbackend.h"
#include "updatebackend.h"
#include "prayerbackend.h"
#include "installerbackend.h"
#include "brightnessbackend.h"
#include "volumebackend.h"
#include "reminderbackend.h"
#include "themebackend.h"
#include "authbackend.h"
#include "debugbackend.h"
#include "systeminfobackend.h"

int main(int argc, char *argv[])
{
    // Force eglfs only if BOTH: (a) the platform wasn't already chosen by
    // the environment, AND (b) there's no existing desktop session
    // (X11/Wayland) already running. eglfs grabs the raw DRM/KMS display
    // and the raw evdev/libinput input devices directly - correct on the
    // bare-metal live ISO (no compositor present at all), but on a dev
    // machine with GNOME/X11/Wayland already running, forcing eglfs makes
    // this app fight the running desktop for the screen AND steal mouse/
    // keyboard input away from it system-wide - which looks exactly like
    // "nothing accepts input anymore", anywhere, the instant the app
    // starts (not something triggered by any specific button). Checking
    // DISPLAY/WAYLAND_DISPLAY is the standard way to detect "a desktop
    // session is already here" - if either is set, let Qt auto-pick the
    // normal xcb/wayland plugin instead, same as any regular desktop app.
    // QT_QPA_PLATFORM=xcb (or =eglfs) can still be set explicitly to
    // override this either direction, on the ISO or on a dev machine.
    if (qEnvironmentVariableIsEmpty("QT_QPA_PLATFORM")) {
        bool hasDesktopSession = !qEnvironmentVariableIsEmpty("DISPLAY")
            || !qEnvironmentVariableIsEmpty("WAYLAND_DISPLAY");
        if (!hasDesktopSession) {
            qputenv("QT_QPA_PLATFORM", "eglfs");
        }
    }

    QGuiApplication app(argc, argv);
    app.setApplicationName("RoohaniyeNooreIlmLinux Shell");

    // IMPORTANT: these must be declared BEFORE QQmlApplicationEngine.
    // C++ destroys local variables in reverse declaration order, so if
    // engine were declared first, it would be destroyed LAST — after
    // these backends were already gone. QML item teardown (which fires
    // Component.onDestruction, e.g. QuranView saving reading progress)
    // only happens when the engine itself is destroyed, so any QML code
    // running during shutdown would be calling into deleted C++ objects.
    // Declaring backends first means they outlive the engine, so QML
    // teardown always has valid objects to call into.
    AppCenter appCenter;
    QuranBackend quranBackend;
    // No cross-backend dependencies (own dedicated SQLite connection),
    // declared here mainly for readability alongside QuranBackend.
    MushafBackend mushafBackend;
    // Declared after QuranBackend (so it's destroyed BEFORE QuranBackend,
    // per the same reverse-destruction-order reasoning as above -
    // AudioBackend holds a raw QuranBackend* and must stop using it
    // before QuranBackend itself goes away).
    AudioBackend audioBackend(&quranBackend);
    WifiBackend wifiBackend;
    PowerBackend powerBackend;
    StorageBackend storageBackend;
    // Holds a raw QuranBackend* (to hot-swap the audio/hadith attachments
    // it owns) - declared after QuranBackend for the same reverse-
    // destruction-order reasoning as AudioBackend above.
    DbConnectorBackend dbConnectorBackend(&quranBackend);
    // No cross-backend dependencies, order doesn't matter for this one.
    UpdateBackend updateBackend;
    // Also no cross-backend dependencies (self-contained: location +
    // calc settings persisted via its own QSettings, no live sensors).
    PrayerBackend prayerBackend;
    // No cross-backend dependencies either (reads live disk state via
    // lsblk/findmnt on demand, doesn't hold a pointer into anything else).
    InstallerBackend installerBackend;
    // Neither holds a pointer into any other backend.
    BrightnessBackend brightnessBackend;
    ThemeBackend themeBackend;
    VolumeBackend volumeBackend;
    ReminderBackend reminderBackend;
    AuthBackend authBackend;
    // Depends on StorageBackend* (reads its already-detected removable
    // device list to know where to write log files) - declared after it
    // for the same reverse-destruction-order reasoning as DbConnectorBackend.
    DebugBackend debugBackend(&storageBackend);
    // No cross-backend dependencies - reads /proc, /sys and
    // QStorageInfo directly, doesn't hold a pointer into anything else.
    SystemInfoBackend systemInfoBackend;

    QQmlApplicationEngine engine;

    // Open before any QML is loaded — QML property bindings can evaluate
    // as soon as a component is created, which can race ahead of a
    // Component.onCompleted handler inside the QML itself.
    // quran_text.db (verses, small) and quran_audio.db (audio blobs,
    // tens of GB) used to be one combined quran_audio_embedded.db file -
    // split via scripts/split_quran_db.py so hot-path text queries never
    // touch the huge audio file. See quranbackend.h for how the two are
    // joined at runtime (ATTACH DATABASE).
    quranBackend.openDatabases(
        "/opt/roohaniye/data/quran_text.db",
        "/opt/roohaniye/data/quran_audio.db",
        "/opt/roohaniye/data/hadiths.db"
    );
    mushafBackend.openDatabase("/opt/roohaniye/data/mushafs.db");

    engine.rootContext()->setContextProperty("appCenter", &appCenter);
    engine.rootContext()->setContextProperty("quranBackend", &quranBackend);
    engine.rootContext()->setContextProperty("mushafBackend", &mushafBackend);
    engine.rootContext()->setContextProperty("audioBackend", &audioBackend);
    engine.rootContext()->setContextProperty("wifiBackend", &wifiBackend);
    engine.rootContext()->setContextProperty("powerBackend", &powerBackend);
    engine.rootContext()->setContextProperty("storageBackend", &storageBackend);
    engine.rootContext()->setContextProperty("dbConnectorBackend", &dbConnectorBackend);
    engine.rootContext()->setContextProperty("updateBackend", &updateBackend);
    engine.rootContext()->setContextProperty("prayerBackend", &prayerBackend);
    engine.rootContext()->setContextProperty("installerBackend", &installerBackend);
    engine.rootContext()->setContextProperty("brightnessBackend", &brightnessBackend);
    engine.rootContext()->setContextProperty("volumeBackend", &volumeBackend);
    engine.rootContext()->setContextProperty("reminderBackend", &reminderBackend);
    engine.rootContext()->setContextProperty("themeBackend", &themeBackend);
    engine.rootContext()->setContextProperty("authBackend", &authBackend);
    engine.rootContext()->setContextProperty("debugBackend", &debugBackend);
    engine.rootContext()->setContextProperty("systemInfoBackend", &systemInfoBackend);
    // Fully-automatic background OS updates: checks periodically,
    // downloads+verifies, and stages for install with no user tap
    // needed - see updatebackend.h for the full check->download->apply
    // handoff and why the actual privileged apply step happens outside
    // this process. This is a deliberate no-safety-net choice; see the
    // same comment for the accepted tradeoff.
    updateBackend.startAutoUpdateCycle();
    // Real touchscreen detection (not a guess/env-var check) - QTouchDevice::devices()
    // reflects what the windowing system (xcb/eglfs) actually reports as
    // registered touch input hardware. Drives the virtual keyboard's
    // auto-show-on-touch-devices default; the user can still flip the
    // Settings toggle either way regardless of what this detects.
    bool hasTouch = !QTouchDevice::devices().isEmpty();
    engine.rootContext()->setContextProperty("hasTouchScreen", hasTouch);

    const QUrl url(QStringLiteral("qrc:/qml/Main.qml"));
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreated,
                      &app, [url](QObject *obj, const QUrl &objUrl) {
                          if (!obj && url == objUrl)
                              QCoreApplication::exit(-1);
                      }, Qt::QueuedConnection);
    engine.load(url);

    return app.exec();
}
