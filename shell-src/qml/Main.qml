import QtQuick 2.15
import QtQuick.Window 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtMultimedia 5.15

Window {
    id: root
    visible: true
    // Only force real fullscreen on the actual eglfs kiosk deployment
    // (raw framebuffer, no window manager - there's no "windowed" mode
    // to speak of there anyway). On a normal desktop session (xcb/
    // wayland, i.e. dev testing on a laptop), stay a plain resizable
    // window instead - this lets portrait-mode scaling/rotation be
    // tested just by dragging the window into a tall, narrow shape with
    // the mouse, with no need to touch real display orientation/xrandr/
    // GNOME Settings at all. width/height below still default to the
    // full screen size on open either way, just resizable afterward
    // when not in the eglfs/FullScreen case.
    visibility: (Qt.platform.pluginName === "eglfs") ? Window.FullScreen : Window.AutomaticVisibility
    width: Screen.width
    height: Screen.height
    x: 0
    y: 0
    color: themeBackend.darkMode ? "#10241f" : "#eef5f1"
    title: "RoohaniyeNooreIlmLinux"

    // Simple stack: home -> quran / hadith / appcenter, animated slide+fade.
    // Boots to the splash screen; SplashScreen.qml advances to "home"
    // itself after a fixed hold time.
    property string currentView: "splash"

    // ---- Real navigation history stack. Every screen used to hardcode
    // its own back-button destination (e.g. QuranView.qml always went to
    // "home", even when it was reached through QuranMenu.qml's pickers) -
    // that's what caused "back sometimes dumps me on the main screen":
    // the hardcoded destination was simply wrong for some entry paths.
    // navigateTo() pushes the screen you're leaving before switching, and
    // goBack() pops it - so back always returns to wherever you actually
    // came from, no matter the path taken to get here. Falls back to
    // "home" if the stack is empty (e.g. Esc-free direct entry, or any
    // future bug) so back can never strand the user on a blank Loader. ----
    property var screenStack: []
    function navigateTo(view) {
        if (currentView !== "" && currentView !== "splash") screenStack.push(currentView)
        currentView = view
    }
    function goBack(fallback) {
        if (screenStack.length > 0) {
            currentView = screenStack.pop()
        } else {
            currentView = fallback || "home"
        }
    }

    // ---- Menu button state: HomeScreen doubles as the "all apps" view
    // (it already lists every section - Quran, Hadith, App Center,
    // Prayer Times, etc), so Menu just navigates there. menuOrigin
    // remembers what was open right before Menu was pressed, so a
    // second Menu press returns to that same app instead of just
    // sitting on Home - "press again to go to the recently opened app"
    // from the spec. Cleared once consumed so a third press (now
    // already back on the recent app) opens the menu fresh again
    // rather than bouncing between only two screens forever. ----
    property string menuOrigin: ""
    function toggleMenu() {
        root.sounds.click()
        if (currentView === "home" && menuOrigin !== "") {
            var target = menuOrigin
            menuOrigin = ""
            root.currentView = target
        } else {
            menuOrigin = currentView
            root.navigateTo("home")
        }
    }

    // ---- Theme helper: a single object every screen can read colors
    // from, so switching dark/light or picking an accent color updates
    // everywhere at once. Screens opt in by using root.theme.bg /
    // .card / .text / .subtext / .accent instead of their own hardcoded
    // hex colors. Currently wired into HomeScreen.qml and
    // SettingsView.qml as the proof of concept and the two most-visited
    // screens; the rest of the app still uses its original fixed dark
    // palette until they're migrated the same way - see continue.md for
    // that as an open follow-up, not a silent gap. ----
    QtObject {
        id: theme
        readonly property bool dark: themeBackend.darkMode
        readonly property color bg: dark ? "#10241f" : "#eef5f1"
        readonly property color card: dark ? "#173832" : "#ffffff"
        readonly property color cardAlt: dark ? "#0f6e56" : "#0f6e56"
        readonly property color text: dark ? "#e8f5ee" : "#16302a"
        readonly property color subtext: dark ? "#8fb3a4" : "#5c7a70"
        readonly property color accent: themeBackend.accentColor
        readonly property bool hasBackground: themeBackend.backgroundImage !== ""
    }
    property alias theme: theme

    // ---- Custom background image: sits behind everything, including
    // the Loader. Screens that want it visible through them set their
    // own root color to "transparent" when theme.hasBackground is true
    // (see HomeScreen.qml) - screens that haven't been migrated yet keep
    // their solid background and simply won't show the image, which is
    // a safe default (no half-transparent unmigrated screens). Stays
    // outside the scaled virtualCanvas below since Image.PreserveAspectCrop
    // already adapts to any real window size on its own - no benefit to
    // routing it through the reference-resolution scale too. ----
    Image {
        anchors.fill: parent
        visible: theme.hasBackground
        source: themeBackend.backgroundImage
        fillMode: Image.PreserveAspectCrop
        opacity: themeBackend.backgroundOpacity
        asynchronous: true
        cache: false
    }

    // ---- On-screen keyboard toggle state. Kept in-memory only (not
    // persisted across launches, since Qt.labs.settings isn't installed
    // on this system and this app avoids pulling in extra Qt modules
    // that need a package install) - it simply defaults to off on every
    // boot, and one tap on vkToggle turns it on for the session. ----
    QtObject {
        id: uiSettings
        // Defaults to on when a real touchscreen is detected (no mouse-
        // only user should have to discover a hidden toggle just to
        // type), off otherwise. Still just a starting point every
        // boot - the toggle button always overrides it for the
        // session, either direction, on any device.
        property bool vkEnabled: hasTouchScreen
    }

    // ---- Automatic screen-resize: every screen in this app was laid
    // out against a 1920x1080 reference (this dev machine's real
    // resolution), with plenty of fixed-pixel icon/font/spacing values
    // that don't reflow on their own. Rather than touch every one of the
    // ~20 QML screens individually, the whole interactive UI is rendered
    // into a fixed 1920x1080 virtualCanvas and then uniformly scaled (and
    // centered/letterboxed if the aspect ratio differs) to fit whatever
    // the real screen size turns out to be - a 7" 1024x600 touch panel
    // shrinks everything proportionally, a 4K panel enlarges it, and
    // Qt Quick's item transforms handle touch/mouse hit-testing through
    // the scale automatically, so nothing about input handling changes. ----
    readonly property real refW: 1920
    readonly property real refH: 1080

    // ---- Orientation: landscape (default) or portrait, toggled via F4
    // or the global orientation button (present on every screen, not
    // just Settings - see orientationToggle below), and also seeded
    // from/kept in sync with the OS-reported physical screen rotation
    // via Screen.primaryOrientation. autoOrientation is a plain binding
    // so it re-evaluates live if the platform reports a rotation change
    // (e.g. an external xrandr/eglfs rotate) - orientationMode follows
    // it automatically UNTIL the user manually toggles once, at which
    // point the manual choice wins for the rest of the session (a user
    // who explicitly asked for portrait shouldn't get silently flipped
    // back by a stale/spurious platform orientation reading).
    readonly property string autoOrientation: {
        var o = Screen.primaryOrientation
        return (o === Qt.PortraitOrientation || o === Qt.InvertedPortraitOrientation)
            ? "portrait" : "landscape"
    }
    property bool orientationManual: false
    property string orientationMode: autoOrientation
    onAutoOrientationChanged: if (!orientationManual) orientationMode = autoOrientation
    function toggleOrientation() {
        orientationManual = true
        orientationMode = (orientationMode === "landscape") ? "portrait" : "landscape"
        root.sounds.click()
    }
    readonly property bool portrait: orientationMode === "portrait"

    // ---- Automatic screen-resize: every screen in this app was laid
    // out against a 1920x1080 reference (this dev machine's real
    // resolution), with plenty of fixed-pixel icon/font/spacing values
    // that don't reflow on their own. Rather than touch every one of the
    // ~20 QML screens individually, the whole interactive UI is rendered
    // into a fixed 1920x1080 virtualCanvas and then uniformly scaled (and
    // centered/letterboxed if the aspect ratio differs) to fit whatever
    // the real screen size turns out to be - a 7" 1024x600 touch panel
    // shrinks everything proportionally, a 4K panel enlarges it, and
    // Qt Quick's item transforms handle touch/mouse hit-testing through
    // the scale automatically, so nothing about input handling changes.
    // In portrait mode the canvas is additionally rotated 90 degrees
    // (see virtualCanvas.rotation below) - the available space for
    // fitting it is therefore the window's height/width SWAPPED, since
    // a landscape-authored 1920x1080 canvas rotated on its side occupies
    // a portrait-shaped footprint. ----
    // NOTE: uiScale is NOT simply availW/refW & availH/refH with availW/
    // availH swapped for portrait - that under-scales, because rotating
    // the canvas ALSO swaps which ref dimension (refW vs refH) maps onto
    // which available dimension. In portrait, after the 90deg rotation
    // below, the canvas's rendered footprint is refH-wide x refW-tall (its
    // own width/height are swapped by the rotation) - so it must be fit
    // by comparing width against refH and height against refW, not
    // against refW/refH straight. Skipping this second swap was the bug:
    // it produced a valid-looking but too-small scale (e.g. 0.5625
    // instead of 1 on a 1920x1080 panel), which is why portrait rotated
    // but never filled the screen. Landscape has no such swap since
    // there's no rotation, so it stays refW/refH as before.
    // Guarded against width/height still being 0 for the first frame or
    // two before the window manager assigns real geometry (confirmed via
    // headless testing) - without this, the whole UI would render at
    // scale 0 (invisible) for a brief moment on every real boot.
    readonly property real uiScale: (width > 0 && height > 0)
        ? (portrait
            ? Math.min(width / refH, height / refW)
            : Math.min(width / refW, height / refH))
        : 1

    Item {
        id: virtualCanvas
        width: root.refW
        height: root.refH
        scale: root.uiScale
        rotation: root.portrait ? 90 : 0
        transformOrigin: Item.Center
        anchors.centerIn: parent

        // ---- Audio safety net: whenever currentView changes AWAY from
        // the Quran reader (goBack, navigateTo, or any other path - this
        // fires regardless of how the change happened), stop any
        // in-progress recitation. Previously the reader's back button
        // only saved reading progress and never touched audioBackend, so
        // leaving the screen while a verse/selection/range was playing
        // left it running with no way to reach it again. QuranView.qml's
        // own back handler also calls stop() directly now, as a second,
        // redundant guard. ----
        Loader {
            id: viewLoader
            anchors.fill: parent
            source: {
                if (currentView === "splash") return "SplashScreen.qml"
                if (currentView === "home") return "HomeScreen.qml"
                if (currentView === "appcenter") return "AppCenter.qml"
                if (currentView === "quranmenu") return "QuranMenu.qml"
                if (currentView === "mushafgallery") return "MushafGallery.qml"
                if (currentView === "mushafreader") return "MushafReader.qml"
                if (currentView === "quranreader") return "QuranView.qml"
                if (currentView === "quran") return "QuranView.qml" // legacy direct-to-reader route, kept as an alias
                if (currentView === "aboutquran") return "AboutQuran.qml"
                if (currentView === "hadith") return "HadithMenu.qml"
                if (currentView === "hadithreader") return "HadithView.qml"
                if (currentView === "settings") return "SettingsView.qml"
                if (currentView === "dbconnector") return "DatabaseConnector.qml"
                if (currentView === "updates") return "UpdatesView.qml"
                if (currentView === "prayertimes") return "PrayerTimesView.qml"
                if (currentView === "qibla") return "QiblaView.qml"
                if (currentView === "installer") return "InstallerWizard.qml"
                if (currentView === "reminders") return "RemindersView.qml"
                if (currentView === "debug") return "DebugConsoleView.qml"
                return "HomeScreen.qml"
            }

            opacity: 0
            Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            onLoaded: opacity = 1

            onSourceChanged: opacity = 0
        }

        Rectangle {
            id: osd
            function show(iconText, level) {
                osd.icon = iconText
                osd.level = level
                osd.opacity = 1
                hideTimer.restart()
            }
            property string icon: "\u2600"
            property int level: 0

            anchors.horizontalCenter: parent.horizontalCenter
            y: 48
            width: 180
            height: 64
            radius: 16
            color: "#173832"
            opacity: 0
            z: 1000
            Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

            Timer { id: hideTimer; interval: 1200; onTriggered: osd.opacity = 0 }

            Row {
                anchors.centerIn: parent
                spacing: 12
                Text { text: osd.icon; font.pixelSize: 20; anchors.verticalCenter: parent.verticalCenter }
                Rectangle {
                    width: 96; height: 6; radius: 3
                    color: "#0f2b25"
                    anchors.verticalCenter: parent.verticalCenter
                    Rectangle {
                        width: parent.width * (osd.level / 100)
                        height: parent.height
                        radius: 3
                        color: "#7fd6b4"
                        Behavior on width { NumberAnimation { duration: 150 } }
                    }
                }
            }
        }

        // ---- Reminder banner: fires regardless of which screen is
        // open, since reminderBackend polls on its own timer independent
        // of QML navigation. Plays the ringtone once and shows a
        // full-width banner until dismissed - deliberately not
        // auto-dismissing itself (unlike the small brightness/volume OSD
        // above), since a reminder that silently vanishes after a couple
        // seconds while the user's away from the screen defeats the
        // point of having it. ----
        Rectangle {
            id: reminderBanner
            property string text: ""
            visible: false
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.topMargin: 40
            width: Math.min(360, parent.width - 40)
            height: 68
            radius: 18
            color: "#0f6e56"
            z: 1001
            border.width: 1
            border.color: "#7fd6b4"

            RowLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 12
                Text { text: "\u23F0"; font.pixelSize: 22 }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    Text { text: "Reminder"; color: "#bfe9d8"; font.pixelSize: 11 }
                    Text { text: reminderBanner.text; color: "#ffffff"; font.pixelSize: 15; font.weight: Font.Medium; elide: Text.ElideRight }
                }
                Text {
                    text: "\u2715"
                    color: "#bfe9d8"
                    font.pixelSize: 16
                    MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: reminderBanner.visible = false }
                }
            }
        }

        // ---- Global Home / Menu / Back / Orientation cluster: floating,
        // bottom-left, present on every screen via Main.qml (rather than
        // added to each of the ~20 individual screen files) so it can
        // never be missing from one by omission. Only hidden on splash
        // (boot) and the lock screen (that already covers the whole
        // window at z:5000, above this) - shown on Home too, unlike the
        // original cut, because the Menu button's "press again to
        // return" behavior below only makes sense if it's still tappable
        // once Home is showing. Back re-uses root.goBack() - the same
        // real navigation history every screen's own back button already
        // uses - so this is a second entry point to the same function,
        // not a competing implementation. Orientation toggle lives here
        // (not just in Settings) per spec: "the btn should be everywhere
        // not just in settings". ----
        Row {
            id: navCluster
            visible: currentView !== "splash"
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.margins: 22
            spacing: 14
            z: 2000

            Rectangle {
                width: 56; height: 56; radius: 28
                color: theme.dark ? "#173832" : "#ffffff"
                border.width: 1
                border.color: theme.dark ? "#22493f" : "#d7e6df"
                Text { anchors.centerIn: parent; text: "\u2190"; font.pixelSize: 22; color: theme.subtext }
                MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: { root.sounds.click(); root.goBack() } }
            }
            Rectangle {
                width: 56; height: 56; radius: 28
                color: theme.dark ? "#173832" : "#ffffff"
                border.width: 1
                border.color: theme.dark ? "#22493f" : "#d7e6df"
                Text { anchors.centerIn: parent; text: "\u2302"; font.pixelSize: 22; color: theme.subtext }
                MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: { root.sounds.click(); root.menuOrigin = ""; root.currentView = "home"; root.screenStack = [] } }
            }
            Rectangle {
                width: 56; height: 56; radius: 28
                color: (currentView === "home" && menuOrigin !== "") ? theme.accent : (theme.dark ? "#173832" : "#ffffff")
                border.width: 1
                border.color: theme.dark ? "#22493f" : "#d7e6df"
                Text {
                    anchors.centerIn: parent
                    text: "\u2630"
                    font.pixelSize: 20
                    color: (currentView === "home" && menuOrigin !== "") ? "#ffffff" : theme.subtext
                }
                MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: root.toggleMenu() }
            }
            Rectangle {
                width: 56; height: 56; radius: 28
                color: theme.dark ? "#173832" : "#ffffff"
                border.width: 1
                border.color: theme.dark ? "#22493f" : "#d7e6df"
                Text { anchors.centerIn: parent; text: "\u27F3"; font.pixelSize: 22; color: theme.subtext }
                MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: root.toggleOrientation() }
            }
        }

        // ---- On-screen keyboard toggle: a small always-present floating
        // button (bottom-right corner, out of the way of normal
        // content). Purely additive - a physical keyboard or a mouse
        // keeps working exactly as before whether this is toggled on or
        // off, since the keyboard below only ever writes into whatever
        // field already has focus, it never grabs or blocks input. ----
        Rectangle {
            id: vkToggle
            width: 56; height: 56; radius: 28
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 22
            z: 2000
            color: uiSettings.vkEnabled ? theme.accent : (theme.dark ? "#173832" : "#ffffff")
            border.width: 1
            border.color: theme.dark ? "#22493f" : "#d7e6df"
            Text {
                anchors.centerIn: parent
                text: "\u2328"
                font.pixelSize: 24
                color: uiSettings.vkEnabled ? "#ffffff" : theme.subtext
            }
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    uiSettings.vkEnabled = !uiSettings.vkEnabled
                    root.sounds.click()
                }
            }
        }

        // ---- The on-screen keyboard itself. Only instantiated (Loader
        // active) once the toggle above is switched on, so devices that
        // never touch it don't pay for it. When on, it behaves like a
        // phone keyboard: slides up automatically whenever a real text
        // field gains focus, and slides back down otherwise - no need to
        // manually summon it for every field. ----
        readonly property bool vkTargetIsText: viewLoader.item !== null
            && root.activeFocusItem !== null
            && typeof root.activeFocusItem.insert === "function"
            && typeof root.activeFocusItem.cursorPosition === "number"
        readonly property bool vkShouldShow: uiSettings.vkEnabled && vkTargetIsText

        Loader {
            id: vkLoader
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 320
            z: 2500
            active: uiSettings.vkEnabled
            y: parent.vkShouldShow ? (parent.height - height) : parent.height
            Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            sourceComponent: active ? virtualKeyboardComponent : null
        }
        Component {
            id: virtualKeyboardComponent
            VirtualKeyboard {
                target: root.activeFocusItem
                onHideRequested: uiSettings.vkEnabled = false
                onDoneRequested: {
                    if (root.activeFocusItem && typeof root.activeFocusItem.focus !== "undefined") {
                        root.activeFocusItem.focus = false
                    }
                }
            }
        }
    }

    Component.onCompleted: {
        // DB already opened in main.cpp before QML loaded.
        sounds.bismillah()
    }

    // ---- UI sound effects, shared across every loaded screen. Loader
    // children resolve `root` (and therefore `root.sounds`) through the
    // parent QQmlContext chain, same as they already do for
    // `root.currentView` - no context-property plumbing needed. Kept as
    // one small Item rather than a singleton file since it only needs to
    // exist once, alongside everything else that's global to the window. ----
    Item {
        id: sounds
        SoundEffect { id: clickFx; source: "qrc:/assets/audio/SciFi-MouseClick.wav"; volume: 0.55 }
        SoundEffect { id: selectFx; source: "qrc:/assets/audio/SelectBtnClick.wav"; volume: 0.55 }
        // Filename is a typo in the source asset ("Sleecing") - this is
        // actually the per-item "selecting" tick (an item getting
        // checked/unchecked inside an already-active Select mode), as
        // opposed to selectFx above which is the "Select" mode toggle
        // button itself. Two distinct sounds for two distinct actions.
        SoundEffect { id: itemSelectingFx; source: "qrc:/assets/audio/SleecingSound.wav"; volume: 0.4 }
        // QSoundEffect (above) only reliably decodes short uncompressed
        // WAV via the pulseaudio backend - it failed silently ("Error
        // decoding source") on this compressed MP3. Audio{} instead goes
        // through the same GStreamer pipeline AudioBackend already uses
        // for Quran recitation MP3 playback, which does have mp3 decode
        // support installed on this system (mpg123/avdec_mp3 confirmed
        // present) - so this is the correct element for anything that
        // isn't a short raw WAV.
        Audio { id: ringtoneFx; source: "qrc:/assets/audio/ilm_noor_hai_ringtone.mp3"; volume: 0.7 }
        // Buttons *inside* an app/settings screen (Debug Console rows,
        // Reminders actions, Settings account/power actions, etc.) use
        // this distinct click instead of clickFx above, which stays
        // reserved for opening an app from HomeScreen/Menu. Same MP3
        // decode note as ringtoneFx above applies here - Audio{}, not
        // SoundEffect{}.
        Audio { id: buttonClickFx; source: "qrc:/assets/audio/ButtonClick.mp3"; volume: 0.55 }
        // Played once at startup (see Component.onCompleted below).
        Audio { id: bismillahFx; source: "qrc:/assets/audio/bismillah.mp3"; volume: 0.7 }
        function click() { clickFx.play() }
        function select() { selectFx.play() }
        function itemSelecting() { itemSelectingFx.play() }
        function ringtone() { ringtoneFx.stop(); ringtoneFx.play() }
        function buttonClick() { buttonClickFx.stop(); buttonClickFx.play() }
        function bismillah() { bismillahFx.stop(); bismillahFx.play() }
    }
    property alias sounds: sounds

    property string previousView: ""
    onCurrentViewChanged: {
        if ((previousView === "quranreader" || previousView === "quran") && currentView !== previousView) {
            audioBackend.stop()
        }
        previousView = currentView
    }

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

    // Set by MushafGallery.qml before switching to "mushafreader" - one-shot,
    // consumed and reset by MushafReader.qml's Component.onCompleted, same
    // pattern as the Quran nav properties above.
    property string navMushafName: ""
    property int navMushafPage: -1

    // Set by HadithMenu.qml's openReader() before switching to
    // "hadithreader"; HadithView.qml consumes these once on load and
    // resets them (book/topic to "", id to -1, selection to []), same
    // one-shot pattern as the Quran nav properties above.
    property string navHadithBook: ""
    property string navHadithTopic: ""
    property int navHadithId: -1
    property var navHadithSelection: []

    // Dev-only: Esc quits, regardless of what currently has keyboard focus.
    // In production kiosk mode this shortcut can simply be removed/disabled,
    // but during development it's what saves you from hard-rebooting.
    Shortcut {
        sequence: "Esc"
        onActivated: Qt.quit()
    }

    // ---- Hardware media keys: laptop Fn row AND phone-style volume
    // rocker both surface as the same Linux input keycodes (KEY_VOLUMEUP/
    // DOWN/MUTE, KEY_BRIGHTNESSUP/DOWN), which Qt's evdev/eglfs input
    // handling maps to the same Qt::Key_* values either way - one set of
    // bindings covers both kinds of hardware. Global (no focus scope), so
    // they work no matter which screen is open. ----
    Shortcut { sequence: Qt.Key_VolumeUp; onActivated: volumeBackend.increase() }
    Shortcut { sequence: Qt.Key_VolumeDown; onActivated: volumeBackend.decrease() }
    Shortcut { sequence: Qt.Key_VolumeMute; onActivated: volumeBackend.toggleMute() }
    Shortcut { sequence: Qt.Key_MonBrightnessUp; onActivated: brightnessBackend.increase() }
    Shortcut { sequence: Qt.Key_MonBrightnessDown; onActivated: brightnessBackend.decrease() }

    // ---- Plain F-row fallbacks: some keyboards/panels don't send the
    // dedicated Key_Volume*/Key_MonBrightness* codes above (no Fn-lock,
    // or a plain USB keyboard with no media row at all), so F1-F3/F5-F6
    // are bound to the same actions as a second, always-available path.
    // Laptop-standard layout: F1 mute, F2 vol-, F3 vol+, F5 brightness-,
    // F6 brightness+. Both bindings can fire for the same physical key
    // on hardware that sends both codes - harmless, since increase/
    // decrease/toggleMute are idempotent-safe single steps either way.
    Shortcut { sequence: "F1"; onActivated: volumeBackend.toggleMute() }
    Shortcut { sequence: "F2"; onActivated: volumeBackend.decrease() }
    Shortcut { sequence: "F3"; onActivated: volumeBackend.increase() }
    Shortcut { sequence: "F5"; onActivated: brightnessBackend.decrease() }
    Shortcut { sequence: "F6"; onActivated: brightnessBackend.increase() }

    // ---- F4: landscape/portrait toggle, same action as the global
    // orientation button in navCluster below - see toggleOrientation()
    // above for the manual-override behavior this triggers.
    Shortcut { sequence: "F4"; onActivated: root.toggleOrientation() }

    // ---- On-screen "phone-like" OSD: briefly shows an icon + level bar
    // whenever brightness/volume changes, whether triggered by a
    // hardware key or a Settings slider drag. Lives inside virtualCanvas
    // above so it scales/positions consistently with everything else. ----
    // Note: osd/reminderBanner are declared inside virtualCanvas above,
    // but QML ids have whole-document scope (not lexical/nesting scope),
    // so referencing them by id from here works exactly as it did before
    // they were moved inside virtualCanvas for scaling.
    Connections {
        target: volumeBackend
        function onVolumeChanged() { osd.show(volumeBackend.muted ? "\u{1F507}" : "\u{1F50A}", volumeBackend.volume) }
        function onMutedChanged() { osd.show(volumeBackend.muted ? "\u{1F507}" : "\u{1F50A}", volumeBackend.volume) }
    }
    Connections {
        target: brightnessBackend
        function onBrightnessChanged() { osd.show("\u2600", brightnessBackend.brightness) }
    }

    Connections {
        target: reminderBackend
        function onReminderDue(id, title) {
            root.sounds.ringtone()
            reminderBanner.text = title
            reminderBanner.visible = true
        }
    }

    // ---- Auth lock/login overlay: sits above absolutely everything
    // (even the reminder banner/OSD/keyboard) so a locked session can
    // never be bypassed by whatever screen happens to be loaded
    // underneath. Deliberately OUTSIDE virtualCanvas and unscaled - a
    // lock screen needs to always be full, real screen size and never
    // be affected by a bug in the scaling math. Loader (not an inline
    // component) so LockScreen.qml, and the authBackend calls it makes,
    // only get instantiated when actually needed - a fresh install with
    // zero accounts never pays for it. ----
    Loader {
        anchors.fill: parent
        z: 5000
        active: authBackend.locked
        sourceComponent: active ? lockScreenComponent : null
    }
    Component {
        id: lockScreenComponent
        LockScreen {}
    }
}
