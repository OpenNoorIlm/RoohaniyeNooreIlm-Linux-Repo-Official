import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15

Rectangle {
    anchors.fill: parent
    color: "#10241f"

    property string selectedSsid: ""
    property string powerAction: ""

    Component.onCompleted: {
        wifiBackend.refreshWifiState()
        if (wifiBackend.wifiEnabled) wifiBackend.scan()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 32
        spacing: 20

        RowLayout {
            Layout.fillWidth: true
            Text {
                text: "\u2190"
                color: "#7fd6b4"
                font.pixelSize: 20
                MouseArea { anchors.fill: parent; onClicked: root.currentView = "home" }
            }
            Text { text: "Settings"; color: "#e8f5ee"; font.pixelSize: 20; font.weight: Font.Medium; Layout.leftMargin: 12 }
        }

        // ---- WiFi toggle row ----
        Rectangle {
            Layout.fillWidth: true
            height: 56
            radius: 14
            color: "#173832"

            RowLayout {
                anchors.fill: parent
                anchors.margins: 16
                Text { text: "WiFi"; color: "#dff2ea"; font.pixelSize: 15 }
                Item { Layout.fillWidth: true }
                Switch {
                    checked: wifiBackend.wifiEnabled
                    onToggled: wifiBackend.setWifiEnabled(checked)
                }
            }
        }

        Text {
            text: wifiBackend.statusMessage
            color: "#8fb3a4"
            font.pixelSize: 12
        }

        // ---- Network list ----
        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: wifiBackend.wifiEnabled
            model: wifiBackend.networks
            spacing: 8
            clip: true

            delegate: Rectangle {
                width: ListView.view.width
                height: 52
                radius: 12
                color: selectedSsid === modelData.ssid ? "#0f6e56" : "#173832"

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    Text { text: modelData.ssid; color: "#dff2ea"; font.pixelSize: 14; Layout.fillWidth: true }
                    Text { text: modelData.secured ? "\ud83d\udd12" : ""; color: "#8fb3a4"; font.pixelSize: 12 }
                    Text { text: modelData.signal + "%"; color: "#8fb3a4"; font.pixelSize: 12 }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        if (modelData.secured) {
                            selectedSsid = modelData.ssid
                            passwordDialog.open()
                        } else {
                            wifiBackend.connectToNetwork(modelData.ssid, "")
                        }
                    }
                }
            }
        }

        // ---- Power controls ----
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Rectangle {
                Layout.fillWidth: true
                height: 48
                radius: 12
                color: "#3c3489"
                Text { anchors.centerIn: parent; text: "Restart"; color: "#fff"; font.pixelSize: 14 }
                MouseArea { anchors.fill: parent; onClicked: { powerAction = "restart"; powerDialog.open() } }
            }
            Rectangle {
                Layout.fillWidth: true
                height: 48
                radius: 12
                color: "#993c1d"
                Text { anchors.centerIn: parent; text: "Shut down"; color: "#fff"; font.pixelSize: 14 }
                MouseArea { anchors.fill: parent; onClicked: { powerAction = "shutdown"; powerDialog.open() } }
            }
        }
    }

    Dialog {
        id: passwordDialog
        anchors.centerIn: parent
        modal: true
        width: 320
        title: "Connect to " + selectedSsid

        contentItem: ColumnLayout {
            spacing: 12
            width: 280
            TextField {
                id: pwField
                placeholderText: "Password"
                echoMode: TextInput.Password
                Layout.fillWidth: true
            }
        }

        footer: DialogButtonBox {
            Button { text: "Cancel"; DialogButtonBox.buttonRole: DialogButtonBox.RejectRole }
            Button { text: "Connect"; DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole }
        }

        onAccepted: wifiBackend.connectToNetwork(selectedSsid, pwField.text)
    }

    Dialog {
        id: powerDialog
        anchors.centerIn: parent
        modal: true
        width: 320
        title: powerAction === "restart" ? "Restart device?" : "Shut down device?"

        contentItem: Text {
            text: powerAction === "restart"
                ? "The device will restart immediately."
                : "The device will power off immediately."
            color: "#dff2ea"
            width: 260
            wrapMode: Text.WordWrap
        }

        footer: DialogButtonBox {
            Button { text: "Cancel"; DialogButtonBox.buttonRole: DialogButtonBox.RejectRole }
            Button {
                text: powerAction === "restart" ? "Restart" : "Shut down"
                DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
            }
        }

        onAccepted: {
            if (powerAction === "restart") powerBackend.restart()
            else powerBackend.shutdown()
        }
    }
}
