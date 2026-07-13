import QtQuick 2.15
import QtQuick.Layouts 1.15

// Boot splash: shown once at startup while the shell is already fully
// loaded underneath (DBs are opened synchronously in main.cpp before any
// QML loads, so there's no real "waiting" happening here - this is a
// deliberate branded moment, not a progress screen for slow I/O). Holds
// for a fixed duration then hands off to Main.qml's Loader by setting
// currentView back to "home".
Rectangle {
    id: splash
    anchors.fill: parent
    color: "#0c1d19"

    // How long the splash stays up before auto-advancing to Home.
    property int holdMs: 2000

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 22

        // ---- Logo mark ----
        // Crescent-and-star glyph in a soft circular badge, built from the
        // same "draw icons with unicode glyphs on plain Rectangles" style
        // used everywhere else in this shell (no image asset pipeline
        // exists yet, so this stays consistent rather than introducing one
        // just for a splash screen).
        Item {
            Layout.alignment: Qt.AlignHCenter
            width: 128; height: 128

            Rectangle {
                id: badge
                anchors.fill: parent
                radius: width / 2
                color: "#173832"
                border.color: "#2f6a55"
                border.width: 2
                scale: 0.7
                opacity: 0

                Text {
                    anchors.centerIn: parent
                    text: "\u262A" // ☪
                    color: "#7fd6b4"
                    font.pixelSize: 62
                }

                SequentialAnimation {
                    running: true
                    NumberAnimation { target: badge; property: "opacity"; to: 1; duration: 480; easing.type: Easing.OutCubic }
                }
                NumberAnimation {
                    target: badge; property: "scale"; to: 1; duration: 560
                    easing.type: Easing.OutBack; running: true
                }
            }

            // Slow ambient pulse ring, purely decorative.
            Rectangle {
                anchors.centerIn: parent
                width: parent.width + 24
                height: parent.height + 24
                radius: width / 2
                color: "transparent"
                border.color: "#1c3830"
                border.width: 1
                opacity: 0.6

                SequentialAnimation on scale {
                    loops: Animation.Infinite
                    running: true
                    NumberAnimation { from: 1.0; to: 1.12; duration: 1400; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 1.12; to: 1.0; duration: 1400; easing.type: Easing.InOutSine }
                }
            }
        }

        // ---- Wordmark ----
        ColumnLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 4
            opacity: 0

            NumberAnimation on opacity {
                to: 1; duration: 500; running: true
                easing.type: Easing.OutCubic
                // slight delay so the badge settles first
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: "RoohaniyeNoorIlmLinux"
                color: "#e8f5ee"
                font.pixelSize: 22
                font.weight: Font.Medium
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: "Reflect. Recite. Reconnect."
                color: "#7fb3a0"
                font.pixelSize: 12
            }
        }

        // ---- Loading dots ----
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 10
            spacing: 8

            Repeater {
                model: 3
                delegate: Rectangle {
                    width: 7; height: 7; radius: 3.5
                    color: "#7fd6b4"

                    SequentialAnimation on opacity {
                        loops: Animation.Infinite
                        running: true
                        PauseAnimation { duration: index * 180 }
                        NumberAnimation { from: 0.25; to: 1.0; duration: 420; easing.type: Easing.InOutSine }
                        NumberAnimation { from: 1.0; to: 0.25; duration: 420; easing.type: Easing.InOutSine }
                    }
                }
            }
        }
    }

    Timer {
        interval: splash.holdMs
        running: true
        onTriggered: root.currentView = "home"
    }
}
