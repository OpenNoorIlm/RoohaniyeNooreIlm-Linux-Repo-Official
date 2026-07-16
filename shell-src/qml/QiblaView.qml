import QtQuick 2.15
import QtQuick.Layouts 1.15

// "Qibla" app: shows the great-circle bearing to the Kaaba from the
// saved location, as a compass-rose graphic. IMPORTANT: this device has
// no magnetometer, so the rose is drawn with N fixed at the top rather
// than tracking the device's real-world heading live - the user has to
// orient the device (or themselves) to true north first, e.g. using a
// separate compass, then read the marked bearing off this screen.
Rectangle {
    id: qiblaRoot
    anchors.fill: parent
    color: "#10241f"

    property var loc: prayerBackend.location()
    property real bearing: loc.hasLocation ? prayerBackend.qiblaBearing() : 0

    function refresh() {
        qiblaRoot.loc = prayerBackend.location()
        qiblaRoot.bearing = qiblaRoot.loc.hasLocation ? prayerBackend.qiblaBearing() : 0
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
                text: "Qibla"
                color: "#e8f5ee"
                font.pixelSize: 20
                font.weight: Font.Medium
                Layout.leftMargin: 12
            }
        }

        // ---- No location set yet ----
        ColumnLayout {
            visible: !qiblaRoot.loc.hasLocation
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 16

            Item { Layout.fillHeight: true }
            Text {
                text: "Set your location to find the qibla direction."
                color: "#8fb3a4"
                font.pixelSize: 14
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
            }
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 220
                Layout.preferredHeight: 48
                radius: 12
                color: "#0f6e56"
                Text { anchors.centerIn: parent; text: "Choose location"; color: "#fff"; font.pixelSize: 14; font.weight: Font.Medium }
                MouseArea { anchors.fill: parent; onClicked: locationLoader.active = true }
            }
            Item { Layout.fillHeight: true }
        }

        // ---- Compass ----
        ColumnLayout {
            visible: qiblaRoot.loc.hasLocation
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 16

            Text {
                text: "This device has no compass sensor. Orient yourself to true north first (e.g. with a separate compass), then face the marked direction below."
                color: "#8fb3a4"
                font.pixelSize: 12
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                Item {
                    id: rose
                    anchors.centerIn: parent
                    width: Math.min(parent.width, parent.height) - 20
                    height: width

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: "#173832"
                        border.color: "#2a5c4f"
                        border.width: 2
                    }

                    // Tick marks every 30 degrees, each rotated as a
                    // full-radius item so its own center sits exactly
                    // on the rose's center - simplest reliable way to
                    // pivot a short mark around the circle's middle.
                    Repeater {
                        model: 12
                        delegate: Item {
                            anchors.fill: rose
                            rotation: index * 30
                            Rectangle {
                                width: 2
                                height: index % 3 === 0 ? 16 : 8
                                radius: 1
                                color: "#3a6b5c"
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.top: parent.top
                                anchors.topMargin: 6
                            }
                        }
                    }

                    Text { text: "N"; color: "#dff2ea"; font.pixelSize: 16; font.weight: Font.Medium; anchors.top: parent.top; anchors.topMargin: 20; anchors.horizontalCenter: parent.horizontalCenter }
                    Text { text: "E"; color: "#8fb3a4"; font.pixelSize: 13; anchors.right: parent.right; anchors.rightMargin: 20; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: "S"; color: "#8fb3a4"; font.pixelSize: 13; anchors.bottom: parent.bottom; anchors.bottomMargin: 20; anchors.horizontalCenter: parent.horizontalCenter }
                    Text { text: "W"; color: "#8fb3a4"; font.pixelSize: 13; anchors.left: parent.left; anchors.leftMargin: 20; anchors.verticalCenter: parent.verticalCenter }

                    // Needle pointing at the qibla bearing (0deg = up/N,
                    // clockwise), pivoted around the rose's center.
                    Item {
                        anchors.fill: parent
                        rotation: qiblaRoot.bearing

                        Rectangle {
                            width: 5
                            height: rose.height / 2 - 34
                            radius: 2.5
                            color: "#0f6e56"
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.verticalCenter
                        }
                        Text {
                            text: "\u25B2"
                            color: "#0f6e56"
                            font.pixelSize: 26
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.verticalCenter
                            anchors.bottomMargin: rose.height / 2 - 34
                        }
                    }

                    Rectangle {
                        width: 14; height: 14; radius: 7
                        color: "#dff2ea"
                        anchors.centerIn: parent
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text {
                    text: qiblaRoot.bearing.toFixed(1) + "\u00b0 from true north"
                    color: "#e8f5ee"
                    font.pixelSize: 16
                    font.weight: Font.Medium
                    Layout.alignment: Qt.AlignHCenter
                }
                Text {
                    text: qiblaRoot.loc.label
                    color: "#8fb3a4"
                    font.pixelSize: 12
                    Layout.alignment: Qt.AlignHCenter
                }
                Text {
                    text: "Change location"
                    color: "#7fd6b4"
                    font.pixelSize: 12
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 4
                    MouseArea { anchors.fill: parent; onClicked: locationLoader.active = true }
                }
            }
        }
    }

    Loader {
        id: locationLoader
        anchors.fill: parent
        active: false
        source: "LocationPicker.qml"
        onLoaded: {
            item.saved.connect(function() { locationLoader.active = false; qiblaRoot.refresh() })
            item.closed.connect(function() { locationLoader.active = false })
        }
    }
}
