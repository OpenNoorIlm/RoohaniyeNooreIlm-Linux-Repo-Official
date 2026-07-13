import QtQuick 2.15
import QtQuick.Layouts 1.15

Rectangle {
    anchors.fill: parent
    color: "#10241f"

    property var hadith: quranBackend.randomHadith()

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 40
        spacing: 24

        // ---- Header ----
        RowLayout {
            Layout.fillWidth: true

            ColumnLayout {
                spacing: 2
                Text {
                    text: "Assalamu alaikum"
                    color: "#e8f5ee"
                    font.pixelSize: 26
                    font.weight: Font.Medium
                }
                Text {
                    text: Qt.formatDateTime(new Date(), "dddd, d MMMM")
                    color: "#8fb3a4"
                    font.pixelSize: 14
                }
            }

            Item { Layout.fillWidth: true }

            Rectangle {
                width: 44; height: 44; radius: 22
                color: "#173832"
                Text { anchors.centerIn: parent; text: "\u2699"; color: "#7fd6b4"; font.pixelSize: 18 }
                MouseArea { anchors.fill: parent; onClicked: root.currentView = "settings" }
            }
        }

        // ---- Big tiles: Quran / Hadith ----
        RowLayout {
            Layout.fillWidth: true
            spacing: 16

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredWidth: 2
                Layout.preferredHeight: 160
                radius: 20
                color: "#0f6e56"
                scale: quranMouse.pressed ? 0.97 : 1.0
                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 20
                    Text { text: "Quran"; color: "#ffffff"; font.pixelSize: 19; font.weight: Font.Medium }
                    Item { Layout.fillHeight: true }
                    Text { text: "Continue reading"; color: "#bfe9d8"; font.pixelSize: 13 }
                }

                MouseArea {
                    id: quranMouse
                    anchors.fill: parent
                    onClicked: root.currentView = "quranmenu"
                }
            }

            Rectangle {
                Layout.preferredWidth: 160
                Layout.preferredHeight: 160
                radius: 20
                color: "#3c3489"
                scale: hadithMouse.pressed ? 0.97 : 1.0
                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 20
                    Text { text: "Hadith"; color: "#ffffff"; font.pixelSize: 17; font.weight: Font.Medium }
                    Item { Layout.fillHeight: true }
                    Text {
                        text: "Daily hadith"
                        color: "#beb9ec"
                        font.pixelSize: 12
                    }
                }

                MouseArea {
                    id: hadithMouse
                    anchors.fill: parent
                    onClicked: root.currentView = "hadith"
                }
            }
        }

        // ---- App grid ----
        Text { text: "Apps"; color: "#8fb3a4"; font.pixelSize: 13; font.weight: Font.Medium }

        GridLayout {
            Layout.fillWidth: true
            columns: 4
            columnSpacing: 14
            rowSpacing: 14

            Repeater {
                model: [
                    { icon: "\u25A6", label: "App center", view: "appcenter", requiresStorage: false },
                    { icon: "\u23F0", label: "Prayer times", view: "prayertimes", requiresStorage: false },
                    { icon: "\u2726", label: "Qibla", view: "qibla", requiresStorage: false },
                    { icon: "\u27F3", label: "Updates", view: "updates", requiresStorage: false },
                    { icon: "\u{1F5C4}", label: "DB Connector", view: "dbconnector", requiresStorage: true }
                ]

                delegate: Rectangle {
                    // Tiles that need a storage device (currently only DB
                    // Connector) grey out and stop responding to taps
                    // until storageBackend.storagePresent flips true -
                    // see storagebackend.h/.cpp (polls /media, /run/media).
                    readonly property bool tileEnabled: !modelData.requiresStorage || storageBackend.storagePresent

                    Layout.preferredWidth: 130
                    Layout.preferredHeight: 100
                    radius: 16
                    color: "#173832"
                    opacity: tileEnabled ? 1.0 : 0.4
                    scale: tileMouse.pressed && tileEnabled ? 0.95 : 1.0
                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                    Behavior on opacity { NumberAnimation { duration: 200 } }

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 8
                        Text { text: modelData.icon; color: "#7fd6b4"; font.pixelSize: 22; Layout.alignment: Qt.AlignHCenter }
                        Text { text: modelData.label; color: "#dff2ea"; font.pixelSize: 12; Layout.alignment: Qt.AlignHCenter }
                        Text {
                            visible: modelData.requiresStorage && !storageBackend.storagePresent
                            text: "Insert USB/SD"
                            color: "#6f9585"
                            font.pixelSize: 9
                            Layout.alignment: Qt.AlignHCenter
                        }
                    }

                    MouseArea {
                        id: tileMouse
                        anchors.fill: parent
                        enabled: tileEnabled
                        onClicked: root.currentView = modelData.view
                    }
                }
            }
        }

        Item { Layout.fillHeight: true }
    }
}
