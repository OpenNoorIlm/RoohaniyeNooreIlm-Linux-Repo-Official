import QtQuick 2.15
import QtQuick.Layouts 1.15

// "Updates" app: check the official distro-download repo for a newer OS
// image, download + sha256-verify it. Backed by updateBackend. Does NOT
// apply/flash the update automatically - see updatebackend.h for why;
// once downloaded+verified this screen just shows applyInstructions().
Rectangle {
    id: updatesRoot
    anchors.fill: parent
    color: "#10241f"

    property bool checked: false
    property bool available: false
    property string latestVersion: ""
    property string releaseNotes: ""
    property bool downloaded: false
    property string downloadedPath: ""
    property string downloadError: ""

    Connections {
        target: updateBackend
        function onCheckFinished(avail, latest, notes) {
            updatesRoot.checked = true
            updatesRoot.available = avail
            updatesRoot.latestVersion = latest
            updatesRoot.releaseNotes = notes
        }
        function onDownloadFinished(success, path, message) {
            updatesRoot.downloaded = success
            updatesRoot.downloadedPath = path
            updatesRoot.downloadError = success ? "" : message
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 28
        spacing: 18

        RowLayout {
            Layout.fillWidth: true
            Text {
                text: "\u2190"
                color: "#7fd6b4"
                font.pixelSize: 20
                MouseArea { anchors.fill: parent; onClicked: root.goBack() }
            }
            Text {
                text: "Updates"
                color: "#e8f5ee"
                font.pixelSize: 20
                font.weight: Font.Medium
                Layout.leftMargin: 12
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 90
            radius: 16
            color: "#173832"

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 4
                Text { text: "Installed version"; color: "#8fb3a4"; font.pixelSize: 12 }
                Text { text: updateBackend.currentVersion; color: "#e8f5ee"; font.pixelSize: 22; font.weight: Font.Medium }
            }
        }

        Text {
            text: updateBackend.statusMessage
            color: "#8fb3a4"
            font.pixelSize: 13
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            visible: updateBackend.statusMessage !== ""
        }

        Rectangle {
            visible: !updatesRoot.checked || (updatesRoot.checked && !updatesRoot.available)
            Layout.fillWidth: true
            Layout.preferredHeight: 48
            radius: 12
            color: "#0f6e56"
            opacity: updateBackend.busy ? 0.6 : 1.0
            Text {
                anchors.centerIn: parent
                text: updateBackend.busy ? "Checking\u2026" : "Check for updates"
                color: "#fff"
                font.pixelSize: 14
                font.weight: Font.Medium
            }
            MouseArea {
                anchors.fill: parent
                enabled: !updateBackend.busy
                onClicked: updateBackend.checkForUpdate()
            }
        }

        ColumnLayout {
            visible: updatesRoot.checked && updatesRoot.available
            Layout.fillWidth: true
            spacing: 14

            Rectangle {
                Layout.fillWidth: true
                radius: 16
                color: "#173832"
                Layout.preferredHeight: notesCol.height + 32

                ColumnLayout {
                    id: notesCol
                    x: 16; y: 16
                    width: parent.width - 32
                    spacing: 6
                    Text {
                        text: "Update available: " + updatesRoot.latestVersion
                        color: "#7fd6b4"
                        font.pixelSize: 15
                        font.weight: Font.Medium
                    }
                    Text {
                        visible: updatesRoot.releaseNotes !== ""
                        text: updatesRoot.releaseNotes
                        color: "#bfe9d8"
                        font.pixelSize: 13
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }
            }

            Rectangle {
                visible: !updatesRoot.downloaded
                Layout.fillWidth: true
                Layout.preferredHeight: 48
                radius: 12
                color: "#0f6e56"
                opacity: updateBackend.busy ? 0.6 : 1.0
                Text {
                    anchors.centerIn: parent
                    text: updateBackend.busy ? "Downloading\u2026" : "Download & verify"
                    color: "#fff"
                    font.pixelSize: 14
                    font.weight: Font.Medium
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: !updateBackend.busy
                    onClicked: updateBackend.downloadUpdate()
                }
            }

            Text {
                visible: updatesRoot.downloadError !== ""
                text: updatesRoot.downloadError
                color: "#f2a3a3"
                font.pixelSize: 13
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            ColumnLayout {
                visible: updatesRoot.downloaded
                spacing: 8
                Layout.fillWidth: true
                Text {
                    text: "\u2713 Downloaded and verified"
                    color: "#7fd6b4"
                    font.pixelSize: 15
                    font.weight: Font.Medium
                }
                Text {
                    text: updatesRoot.downloadedPath
                    color: "#8fb3a4"
                    font.pixelSize: 11
                    elide: Text.ElideMiddle
                    Layout.fillWidth: true
                }
                Text {
                    text: updateBackend.applyInstructions()
                    color: "#c9b98a"
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
            }
        }

        Item { Layout.fillHeight: true }
    }
}
