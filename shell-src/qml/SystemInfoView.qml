// SystemInfoView: full detail screen backing the "System Info" link in
// QuickSettingsPanel. Reads entirely from systemInfoBackend (see
// systeminfobackend.h/.cpp) - CPU/mem/GPU/disk/battery/uptime, all
// read-only. Calls refreshNow() on open so numbers aren't stale for up
// to ~10s while waiting for the backend's own poll tick (disk usage in
// particular is throttled to every 5th 2s tick = ~10s in the background).
import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15

Rectangle {
    anchors.fill: parent
    color: root.theme.hasBackground ? "transparent" : root.theme.bg

    Component.onCompleted: systemInfoBackend.refreshNow()

    ScrollView {
        anchors.fill: parent
        anchors.margins: 32
        clip: true
        contentWidth: availableWidth

        ColumnLayout {
            width: parent.width
            spacing: 20

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "\u2190"
                    color: root.theme.accent
                    font.pixelSize: 20
                    MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: { root.sounds.buttonClick(); root.goBack() } }
                }
                Text { text: "System Info"; color: root.theme.text; font.pixelSize: 20; font.weight: Font.Medium; Layout.leftMargin: 12 }
                Item { Layout.fillWidth: true }
                Text {
                    text: "\u27F3  Refresh"
                    color: root.theme.subtext
                    font.pixelSize: 13
                    MouseArea { anchors.fill: parent; anchors.margins: -8; onClicked: { root.sounds.buttonClick(); systemInfoBackend.refreshNow() } }
                }
            }

            // ---- Overview card: hostname / kernel / uptime ----
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: overviewCol.implicitHeight + 32
                radius: 14
                color: root.theme.card
                ColumnLayout {
                    id: overviewCol
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 10
                    InfoRow2 { label2: "Hostname"; value2: systemInfoBackend.hostname }
                    InfoRow2 { label2: "Kernel"; value2: systemInfoBackend.kernelVersion }
                    InfoRow2 { label2: "Uptime"; value2: systemInfoBackend.uptimeString }
                }
            }

            // ---- CPU card ----
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: cpuCol.implicitHeight + 32
                radius: 14
                color: root.theme.card
                ColumnLayout {
                    id: cpuCol
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 10
                    Text { text: "Processor"; color: root.theme.text; font.pixelSize: 15; font.weight: Font.Medium }
                    InfoRow2 { label2: "Model"; value2: systemInfoBackend.cpuModel }
                    InfoRow2 { label2: "Cores"; value2: systemInfoBackend.cpuCores }
                    UsageBar2 { label2: "Usage"; percent2: systemInfoBackend.cpuUsagePercent }
                }
            }

            // ---- Memory card ----
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: memCol.implicitHeight + 32
                radius: 14
                color: root.theme.card
                ColumnLayout {
                    id: memCol
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 10
                    Text { text: "Memory"; color: root.theme.text; font.pixelSize: 15; font.weight: Font.Medium }
                    InfoRow2 { label2: "Used"; value2: systemInfoBackend.memUsedMB + " MB / " + systemInfoBackend.memTotalMB + " MB" }
                    UsageBar2 { label2: "Usage"; percent2: systemInfoBackend.memUsagePercent }
                }
            }

            // ---- GPU card ----
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: gpuCol.implicitHeight + 32
                radius: 14
                color: root.theme.card
                ColumnLayout {
                    id: gpuCol
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 10
                    Text { text: "Graphics"; color: root.theme.text; font.pixelSize: 15; font.weight: Font.Medium }
                    InfoRow2 { label2: "GPU"; value2: systemInfoBackend.gpuModel }
                }
            }

            // ---- Battery card ----
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: battCol.implicitHeight + 32
                radius: 14
                color: root.theme.card
                visible: systemInfoBackend.batteryPresent
                ColumnLayout {
                    id: battCol
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 10
                    Text { text: "Battery"; color: root.theme.text; font.pixelSize: 15; font.weight: Font.Medium }
                    InfoRow2 { label2: "Status"; value2: systemInfoBackend.batteryCharging ? "Charging" : "Discharging" }
                    UsageBar2 { label2: "Charge"; percent2: systemInfoBackend.batteryPercent }
                }
            }

            // ---- Disk usage card ----
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: diskCol.implicitHeight + 32
                radius: 14
                color: root.theme.card
                ColumnLayout {
                    id: diskCol
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 14
                    Text { text: "Storage"; color: root.theme.text; font.pixelSize: 15; font.weight: Font.Medium }
                    Repeater {
                        model: systemInfoBackend.diskUsage
                        delegate: ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            InfoRow2 { label2: modelData.mount; value2: modelData.usedMB + " MB / " + modelData.totalMB + " MB" }
                            UsageBar2 { label2: modelData.device; percent2: modelData.percent }
                        }
                    }
                    Text {
                        visible: systemInfoBackend.diskUsage.length === 0
                        text: "No mounted volumes detected"
                        color: root.theme.subtext
                        font.pixelSize: 12
                    }
                }
            }

            Item { Layout.preferredHeight: 40 }
        }
    }

    // ---- Small reusable label/value row, kept local to this file
    // (component id InfoRow2 to avoid clashing with any similarly-named
    // component already used elsewhere in the app). ----
    component InfoRow2: RowLayout {
        property string label2: ""
        property string value2: ""
        Layout.fillWidth: true
        Text { text: label2; color: root.theme.subtext; font.pixelSize: 13 }
        Item { Layout.fillWidth: true }
        Text { text: value2; color: root.theme.text; font.pixelSize: 13; elide: Text.ElideRight }
    }

    component UsageBar2: ColumnLayout {
        property string label2: ""
        property int percent2: 0
        Layout.fillWidth: true
        spacing: 4
        RowLayout {
            Layout.fillWidth: true
            Text { text: label2; color: root.theme.subtext; font.pixelSize: 11 }
            Item { Layout.fillWidth: true }
            Text { text: percent2 + "%"; color: root.theme.subtext; font.pixelSize: 11 }
        }
        Rectangle {
            Layout.fillWidth: true
            height: 6
            radius: 3
            color: root.theme.dark ? "#0f2b25" : "#dce8e2"
            Rectangle {
                width: parent.width * (percent2 / 100)
                height: parent.height
                radius: 3
                color: root.theme.accent
                Behavior on width { NumberAnimation { duration: 200 } }
            }
        }
    }
}
