import QtQuick 2.15
import QtQuick.Layouts 1.15

// Full-screen overlay: pick a reciter for audio playback. Emits
// picked(reciterId). List comes from quranBackend.reciterList() - only
// reciters actually present in the audio_files table, each with a
// display name and Murattal/Mujawwad style label where known.
Rectangle {
    id: picker
    anchors.fill: parent
    color: "#10241f"
    z: 50

    property string currentReciterId: ""

    signal picked(string reciterId)
    signal closed()

    property var reciters: quranBackend.reciterList()

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
                MouseArea { anchors.fill: parent; onClicked: picker.closed() }
            }
            Text {
                text: "Reciter"
                color: "#e8f5ee"
                font.pixelSize: 20
                font.weight: Font.Medium
                Layout.leftMargin: 12
            }
        }

        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 10
            model: picker.reciters

            delegate: Rectangle {
                width: ListView.view.width
                height: 64
                radius: 14
                color: modelData.id === picker.currentReciterId ? "#0f6e56" : "#173832"

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    ColumnLayout {
                        spacing: 2
                        Layout.fillWidth: true
                        Text { text: modelData.name; color: "#e8f5ee"; font.pixelSize: 15; font.weight: Font.Medium }
                        Text { text: modelData.style || ""; color: modelData.id === picker.currentReciterId ? "#bfe9d8" : "#8fb3a4"; font.pixelSize: 11 }
                    }
                    Text {
                        visible: modelData.id === picker.currentReciterId
                        text: "\u2713"
                        color: "#ffffff"
                        font.pixelSize: 16
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: picker.picked(modelData.id)
                }
            }
        }
    }
}
