// TopBar: Ubuntu-style status bar. Centered clock, right-side glance
// cluster (wifi / volume / battery). Tapping the right cluster opens
// QuickSettingsPanel (a dropdown with live controls + a link into the
// full SystemInfoView). Purely a glance/shortcut surface - every value
// shown here is also visible in more detail in QuickSettingsPanel or
// SystemInfoView, so this bar never needs its own separate backend
// state beyond what wifiBackend/volumeBackend/brightnessBackend/
// systemInfoBackend already expose.
import QtQuick 2.15
import QtQuick.Layouts 1.15

Rectangle {
    id: topBar
    height: 40
    color: root.theme.dark ? "#0d1f1a" : "#e4ede8"
    z: 3000

    property bool panelOpen: false

    // Live clock - plain JS Date via a 1s timer. Deliberately not routed
    // through systemInfoBackend (which polls at 2s and is about system
    // resource stats, not wall-clock time) - a clock that's up to 2s
    // stale would be a visible, pointless regression from a 1s-accurate
    // one for zero benefit.
    property string timeString: Qt.formatDateTime(new Date(), "MMM d  hh:mm")
    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: topBar.timeString = Qt.formatDateTime(new Date(), "MMM d  hh:mm")
    }

    Text {
        anchors.centerIn: parent
        text: topBar.timeString
        color: root.theme.accent
        font.pixelSize: 15
        font.weight: Font.Medium
    }

    Row {
        id: glanceCluster
        anchors.right: parent.right
        anchors.rightMargin: 18
        anchors.verticalCenter: parent.verticalCenter
        spacing: 14

        Text {
            visible: brightnessBackend.available
            text: "\u2600"
            color: root.theme.subtext
            font.pixelSize: 15
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            // No live "connected to SSID" signal exposed by wifiBackend
            // yet (see wifibackend.h - networks()/scan() only, no
            // always-on connection-state property) - this glyph only
            // reflects the radio on/off state, same info the slash
            // communicates. Full detail (scan, connect, forget) stays in
            // Settings -> Wifi, unchanged by this bar.
            text: wifiBackend.wifiEnabled ? "\u{1F4F6}" : "\u{1F4F5}"
            color: root.theme.subtext
            font.pixelSize: 15
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            visible: volumeBackend.available
            text: volumeBackend.muted ? "\u{1F507}" : "\u{1F50A}"
            color: root.theme.subtext
            font.pixelSize: 15
            anchors.verticalCenter: parent.verticalCenter
        }

        Row {
            visible: systemInfoBackend.batteryPresent
            spacing: 4
            anchors.verticalCenter: parent.verticalCenter
            Text {
                text: systemInfoBackend.batteryCharging ? "\u26A1" : "\u{1F50B}"
                color: root.theme.subtext
                font.pixelSize: 14
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: systemInfoBackend.batteryPercent + "%"
                color: root.theme.text
                font.pixelSize: 13
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    MouseArea {
        anchors.fill: glanceCluster
        anchors.margins: -10
        onClicked: {
            root.sounds.click()
            topBar.panelOpen = !topBar.panelOpen
        }
    }

    Loader {
        anchors.top: parent.bottom
        anchors.right: parent.right
        anchors.rightMargin: 12
        active: topBar.panelOpen
        sourceComponent: active ? quickSettingsComponent : null
        z: 3001
    }
    Component {
        id: quickSettingsComponent
        QuickSettingsPanel {
            onCloseRequested: topBar.panelOpen = false
            onOpenSystemInfo: {
                topBar.panelOpen = false
                root.navigateTo("systeminfo")
            }
        }
    }
}
