// QuickSettingsPanel: dropdown opened by tapping the TopBar glance
// cluster. Root item deliberately covers the WHOLE virtualCanvas (not
// just the panel's own visible size) purely as an invisible tap-to-
// dismiss scrim behind the actual panel card - tapping anywhere outside
// the card closes it, same UX as Ubuntu/Android/iOS quick settings.
import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15

Item {
    id: panelRoot
    // The Loader that hosts this is anchored so its RIGHT edge sits
    // under the glance cluster (see TopBar.qml: anchors.right: parent.right,
    // anchors.rightMargin: 12) while this item's own width is the full
    // canvas width - that makes the Loader span almost the entire
    // screen, which is exactly what's wanted: a full-width invisible
    // dismiss-scrim, with the visible card right-aligned within it so it
    // visually drops down from the glance cluster like a normal popover.
    width: root.refW
    height: root.refH - 40
    z: 3001

    signal closeRequested()
    signal openSystemInfo()

    MouseArea {
        anchors.fill: parent
        onClicked: panelRoot.closeRequested()
    }

    Rectangle {
        id: card
        anchors.right: parent.right
        y: 0
        width: 340
        radius: 16
        color: root.theme.dark ? "#173832" : "#ffffff"
        border.width: 1
        border.color: root.theme.dark ? "#22493f" : "#d7e6df"
        height: contentCol.implicitHeight + 28

        // Absorb clicks on the card itself so they don't fall through
        // to the dismiss-scrim above.
        MouseArea { anchors.fill: parent; onClicked: {} }

        ColumnLayout {
            id: contentCol
            anchors.fill: parent
            anchors.margins: 18
            spacing: 16

            // ---- WiFi ----
            RowLayout {
                Layout.fillWidth: true
                Text { text: "\u{1F4F6}  Wi-Fi"; color: root.theme.text; font.pixelSize: 14 }
                Item { Layout.fillWidth: true }
                Switch {
                    checked: wifiBackend.wifiEnabled
                    onToggled: wifiBackend.setWifiEnabled(checked)
                }
            }
            Text {
                Layout.fillWidth: true
                visible: text !== ""
                text: wifiBackend.statusMessage
                color: root.theme.subtext
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: root.theme.dark ? "#22493f" : "#e4ede8" }

            // ---- Volume ----
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                visible: volumeBackend.available
                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: (volumeBackend.muted ? "\u{1F507}" : "\u{1F50A}") + "  Volume"
                        color: root.theme.text
                        font.pixelSize: 14
                        MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: volumeBackend.toggleMute() }
                    }
                    Item { Layout.fillWidth: true }
                    Text { text: volumeBackend.volume + "%"; color: root.theme.subtext; font.pixelSize: 12 }
                }
                Slider {
                    Layout.fillWidth: true
                    from: 0; to: 100
                    value: volumeBackend.volume
                    onMoved: volumeBackend.setVolume(value)
                }
            }

            // ---- Brightness ----
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                visible: brightnessBackend.available
                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "\u2600  Brightness"; color: root.theme.text; font.pixelSize: 14 }
                    Item { Layout.fillWidth: true }
                    Text { text: brightnessBackend.brightness + "%"; color: root.theme.subtext; font.pixelSize: 12 }
                }
                Slider {
                    Layout.fillWidth: true
                    from: 1; to: 100
                    value: brightnessBackend.brightness
                    onMoved: brightnessBackend.setBrightness(value)
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: root.theme.dark ? "#22493f" : "#e4ede8" }

            // ---- Battery glance ----
            RowLayout {
                Layout.fillWidth: true
                visible: systemInfoBackend.batteryPresent
                Text {
                    text: (systemInfoBackend.batteryCharging ? "\u26A1" : "\u{1F50B}") + "  Battery"
                    color: root.theme.text
                    font.pixelSize: 14
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: systemInfoBackend.batteryPercent + "%" + (systemInfoBackend.batteryCharging ? " (charging)" : "")
                    color: root.theme.subtext
                    font.pixelSize: 12
                }
            }

            // ---- System Info link ----
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 44
                radius: 10
                color: root.theme.accent
                Text {
                    anchors.centerIn: parent
                    text: "System Info"
                    color: "#ffffff"
                    font.pixelSize: 14
                    font.weight: Font.Medium
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: { root.sounds.buttonClick(); panelRoot.openSystemInfo() }
                }
            }
        }
    }
}
