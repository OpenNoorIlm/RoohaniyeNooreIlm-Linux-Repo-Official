import QtQuick 2.15
import QtQuick.Layouts 1.15

Rectangle {
    anchors.fill: parent
    color: root.theme.hasBackground ? "transparent" : root.theme.bg

    // Subtle built-in backdrop texture, shown only when the user hasn't
    // set their own custom background via Settings > Appearance - a
    // user-picked background always takes priority (Main.qml's global
    // Image layer already handles that one; this is a separate, much
    // fainter layer specific to Home so the screen doesn't feel totally
    // flat when no custom background is set).
    Image {
        anchors.fill: parent
        visible: !root.theme.hasBackground
        source: "qrc:/assets/images/home_background.png"
        fillMode: Image.PreserveAspectCrop
        opacity: root.theme.dark ? 0.06 : 0.1
        asynchronous: true
    }

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
                    color: root.theme.text
                    font.pixelSize: 26
                    font.weight: Font.Medium
                }
                Text {
                    text: Qt.formatDateTime(new Date(), "dddd, d MMMM")
                    color: root.theme.subtext
                    font.pixelSize: 14
                }
            }

            Item { Layout.fillWidth: true }

            Rectangle {
                width: 54; height: 54; radius: 27
                color: root.theme.card
                Image {
                    anchors.centerIn: parent
                    width: 28; height: 28
                    source: "qrc:/assets/images/settings_icon.png"
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                }
                MouseArea { anchors.fill: parent; onClicked: { root.sounds.click(); root.navigateTo("settings") } }
            }
        }

        // ---- Install banner: shows once, gone for good after a
        // successful install (installerBackend.isInstalled()). ----
        Rectangle {
            visible: !installerBackend.isInstalled()
            Layout.fillWidth: true
            Layout.preferredHeight: 66
            radius: 16
            color: root.theme.dark ? "#2a4a3f" : "#dcece3"
            border.width: 1
            border.color: root.theme.dark ? "#3d6b5b" : "#b7d8c8"

            RowLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 12
                Image {
                    Layout.preferredWidth: 34; Layout.preferredHeight: 34
                    source: "qrc:/assets/images/installer_icon.png"
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                }
                ColumnLayout {
                    spacing: 1
                    Layout.fillWidth: true
                    Text { text: "You're running the Try session"; color: root.theme.text; font.pixelSize: 13; font.weight: Font.Medium }
                    Text { text: "Install RoohaniyeNooreIlm permanently to a disk"; color: root.theme.subtext; font.pixelSize: 11 }
                }
                Rectangle {
                    Layout.preferredWidth: 74
                    Layout.preferredHeight: 34
                    radius: 10
                    color: root.theme.cardAlt
                    Text { anchors.centerIn: parent; text: "Install"; color: "#fff"; font.pixelSize: 12; font.weight: Font.Medium }
                    MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: { root.sounds.click(); root.navigateTo("installer") } }
                }
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
                color: root.theme.cardAlt
                scale: quranMouse.pressed ? 0.97 : 1.0
                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                Image {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 10
                    width: 62; height: 62
                    opacity: 0.85
                    source: "qrc:/assets/images/quran_icon.png"
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                }

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
                    onClicked: { root.sounds.click(); root.navigateTo("quranmenu") }
                }
            }

            Rectangle {
                Layout.preferredWidth: 160
                Layout.preferredHeight: 160
                radius: 20
                color: "#3c3489"
                scale: hadithMouse.pressed ? 0.97 : 1.0
                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                Image {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 10
                    width: 54; height: 54
                    opacity: 0.85
                    source: "qrc:/assets/images/hadith_icon.png"
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                }

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
                    onClicked: { root.sounds.click(); root.navigateTo("hadith") }
                }
            }
        }

        // ---- App grid ----
        Text { text: "Apps"; color: root.theme.subtext; font.pixelSize: 13; font.weight: Font.Medium }

        GridLayout {
            Layout.fillWidth: true
            columns: 4
            columnSpacing: 14
            rowSpacing: 14

            Repeater {
                model: [
                    { icon: "qrc:/assets/images/appcenter_icon.png", label: "App center", view: "appcenter", requiresStorage: false },
                    { icon: "qrc:/assets/images/prayertimes_icon.png", label: "Prayer times", view: "prayertimes", requiresStorage: false },
                    { icon: "qrc:/assets/images/qibla_icon.png", label: "Qibla", view: "qibla", requiresStorage: false },
                    { icon: "qrc:/assets/images/reminders_icon.png", label: "Reminders", view: "reminders", requiresStorage: false },
                    { icon: "qrc:/assets/images/updates_icon.png", label: "Updates", view: "updates", requiresStorage: false },
                    { icon: "qrc:/assets/images/dbconnector_icon.png", label: "DB Connector", view: "dbconnector", requiresStorage: true }
                ]

                delegate: Rectangle {
                    // Tiles that need a storage device (currently only DB
                    // Connector) grey out and stop responding to taps
                    // until storageBackend.storagePresent flips true -
                    // see storagebackend.h/.cpp (polls /media, /run/media).
                    readonly property bool tileEnabled: !modelData.requiresStorage || storageBackend.storagePresent

                    Layout.preferredWidth: 138
                    Layout.preferredHeight: 112
                    radius: 16
                    color: root.theme.card
                    opacity: tileEnabled ? 1.0 : 0.4
                    scale: tileMouse.pressed && tileEnabled ? 0.95 : 1.0
                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                    Behavior on opacity { NumberAnimation { duration: 200 } }

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 8
                        Image {
                            source: modelData.icon
                            Layout.preferredWidth: 40
                            Layout.preferredHeight: 40
                            Layout.alignment: Qt.AlignHCenter
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                        }
                        Text { text: modelData.label; color: root.theme.text; font.pixelSize: 12; Layout.alignment: Qt.AlignHCenter }
                        Text {
                            visible: modelData.requiresStorage && !storageBackend.storagePresent
                            text: "Insert USB/SD"
                            color: root.theme.subtext
                            font.pixelSize: 9
                            Layout.alignment: Qt.AlignHCenter
                        }
                    }

                    MouseArea {
                        id: tileMouse
                        anchors.fill: parent
                        enabled: tileEnabled
                        onClicked: { root.sounds.click(); root.navigateTo(modelData.view) }
                    }
                }
            }
        }

        Item { Layout.fillHeight: true }
    }
}
