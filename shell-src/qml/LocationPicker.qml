import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15

// Full-screen overlay: set the location used for prayer times + qibla.
// Pick from prayerBackend.cityList() (curated majors), or enter a
// custom lat/lon/UTC-offset directly (no GPS on this hardware target -
// see prayerbackend.h). Calls prayerBackend.setLocation() on save and
// emits saved(); closed() if the user backs out without changing
// anything.
Rectangle {
    id: picker
    anchors.fill: parent
    color: "#10241f"
    z: 60

    signal saved()
    signal closed()

    property var cities: prayerBackend.cityList()
    property bool customMode: false

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 28
        spacing: 16

        RowLayout {
            Layout.fillWidth: true
            Text {
                text: "\u2190"
                color: "#7fd6b4"
                font.pixelSize: 20
                MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: { root.sounds.buttonClick(); picker.closed() } }
            }
            Text {
                text: "Set location"
                color: "#e8f5ee"
                font.pixelSize: 20
                font.weight: Font.Medium
                Layout.leftMargin: 12
            }
        }

        Text {
            text: "Used to calculate prayer times and the qibla direction. No GPS on this device, so pick the closest major city or enter coordinates directly."
            color: "#8fb3a4"
            font.pixelSize: 12
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        // ---- City list ----
        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !picker.customMode
            clip: true
            spacing: 8
            model: picker.cities

            delegate: Rectangle {
                width: ListView.view.width
                height: 52
                radius: 12
                color: "#173832"

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 16
                    text: modelData.name
                    color: "#dff2ea"
                    font.pixelSize: 14
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: { root.sounds.buttonClick();
                        prayerBackend.setLocation(modelData.lat, modelData.lon, modelData.tzOffset, modelData.name)
                        picker.saved()
                    }
                }
            }

            footer: Rectangle {
                width: ListView.view.width
                height: 52
                radius: 12
                color: "#3c3489"
                Text {
                    anchors.centerIn: parent
                    text: "Enter coordinates manually"
                    color: "#fff"
                    font.pixelSize: 14
                }
                MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: { root.sounds.buttonClick(); picker.customMode = true } }
            }
        }

        // ---- Custom lat/lon entry ----
        ColumnLayout {
            visible: picker.customMode
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 12

            TextField {
                id: labelField
                Layout.fillWidth: true
                placeholderText: "Label (e.g. \"Home\")"
            }
            TextField {
                id: latField
                Layout.fillWidth: true
                placeholderText: "Latitude (e.g. 21.4225, negative for South)"
                inputMethodHints: Qt.ImhFormattedNumbersOnly
            }
            TextField {
                id: lonField
                Layout.fillWidth: true
                placeholderText: "Longitude (e.g. 39.8262, negative for West)"
                inputMethodHints: Qt.ImhFormattedNumbersOnly
            }
            TextField {
                id: tzField
                Layout.fillWidth: true
                placeholderText: "UTC offset in hours (e.g. 5.5)"
                inputMethodHints: Qt.ImhFormattedNumbersOnly
            }

            Text {
                id: errorText
                color: "#f2a3a3"
                font.pixelSize: 12
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                visible: text !== ""
            }

            Item { Layout.fillHeight: true }

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Rectangle {
                    Layout.fillWidth: true
                    height: 48
                    radius: 12
                    color: "#173832"
                    Text { anchors.centerIn: parent; text: "Back"; color: "#dff2ea"; font.pixelSize: 14 }
                    MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: { root.sounds.buttonClick(); picker.customMode = false } }
                }
                Rectangle {
                    Layout.fillWidth: true
                    height: 48
                    radius: 12
                    color: "#0f6e56"
                    Text { anchors.centerIn: parent; text: "Save"; color: "#fff"; font.pixelSize: 14; font.weight: Font.Medium }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: { root.sounds.buttonClick();
                            const lat = parseFloat(latField.text)
                            const lon = parseFloat(lonField.text)
                            const tz = parseFloat(tzField.text)
                            if (isNaN(lat) || lat < -90 || lat > 90) {
                                errorText.text = "Latitude must be a number between -90 and 90."
                                return
                            }
                            if (isNaN(lon) || lon < -180 || lon > 180) {
                                errorText.text = "Longitude must be a number between -180 and 180."
                                return
                            }
                            if (isNaN(tz) || tz < -12 || tz > 14) {
                                errorText.text = "UTC offset must be a number between -12 and 14."
                                return
                            }
                            const label = labelField.text.length > 0 ? labelField.text : "Custom location"
                            prayerBackend.setLocation(lat, lon, tz, label)
                            picker.saved()
                        }
                    }
                }
            }
        }
    }
}
