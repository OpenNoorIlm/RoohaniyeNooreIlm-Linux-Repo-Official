import QtQuick 2.15
import QtQuick.Window 2.15
import QtQuick.Controls 2.15

Window {
    id: root
    visible: true
    visibility: Window.FullScreen
    color: "#10241f"
    title: "RoohaniyeNooreIlmLinux"

    // Simple stack: home -> quran / hadith / appcenter, animated slide+fade.
    // Boots to the splash screen; SplashScreen.qml advances to "home"
    // itself after a fixed hold time.
    property string currentView: "splash"

    // Set by SurahPicker/JuzPicker before switching to "quran"/"quranreader"
    // to jump to a specific location; QuranView.qml consumes these on load
    // and resets them to -1. When -1, QuranView resumes from
    // quranBackend.lastProgress().
    property int navSurah: -1
    property int navAyah: -1

    // Set by QuranMenu.qml's openReader() before switching to "quranreader".
    // navPage/navJuz reset to -1 and navLayoutMode resets to "" once
    // QuranView.qml consumes them (same one-shot pattern as navSurah/navAyah).
    property int navPage: -1
    property int navJuz: -1
    property string navLayoutMode: ""

    // Dev-only: Esc quits, regardless of what currently has keyboard focus.
    // In production kiosk mode this shortcut can simply be removed/disabled,
    // but during development it's what saves you from hard-rebooting.
    Shortcut {
        sequence: "Esc"
        onActivated: Qt.quit()
    }

    Component.onCompleted: {
        // DB already opened in main.cpp before QML loaded.
    }

    Loader {
        id: viewLoader
        anchors.fill: parent
        source: {
            if (currentView === "splash") return "SplashScreen.qml"
            if (currentView === "home") return "HomeScreen.qml"
            if (currentView === "appcenter") return "AppCenter.qml"
            if (currentView === "quranmenu") return "QuranMenu.qml"
            if (currentView === "quranreader") return "QuranView.qml"
            if (currentView === "quran") return "QuranView.qml" // legacy direct-to-reader route, kept as an alias
            if (currentView === "aboutquran") return "AboutQuran.qml"
            if (currentView === "hadith") return "HadithView.qml"
            if (currentView === "settings") return "SettingsView.qml"
            if (currentView === "dbconnector") return "DatabaseConnector.qml"
            if (currentView === "updates") return "UpdatesView.qml"
            if (currentView === "prayertimes") return "PrayerTimesView.qml"
            if (currentView === "qibla") return "QiblaView.qml"
            return "HomeScreen.qml"
        }

        opacity: 0
        Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        onLoaded: opacity = 1

        onSourceChanged: opacity = 0
    }
}
