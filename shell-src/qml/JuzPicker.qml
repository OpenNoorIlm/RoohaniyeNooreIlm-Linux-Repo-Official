import QtQuick 2.15
import QtQuick.Layouts 1.15

// Full-screen overlay: pick a juz (1-30) to jump to. Emits picked(juz).
// Also supports a multi-select mode ("Select" toggle in the header): tap
// juzs to check them, then tap "Play (N)" to emit playSelected(items) -
// an array of {type:"juz", juz:N} objects. Order doesn't matter to the
// consumer, which re-sorts into Quran order via
// QuranBackend::versesForSelection().
Rectangle {
    id: picker
    anchors.fill: parent
    color: "#10241f"
    z: 50

    signal picked(int juz)
    signal closed()
    signal playSelected(var items)

    property bool selectionMode: false
    property var selectedJuzs: []

    function isSelected(j) { return selectedJuzs.indexOf(j) !== -1 }
    function toggleSelected(j) {
        var idx = selectedJuzs.indexOf(j)
        var arr = selectedJuzs.slice()
        if (idx === -1) arr.push(j)
        else arr.splice(idx, 1)
        selectedJuzs = arr
    }
    function confirmSelection() {
        var items = selectedJuzs.map(function(j) { return {type: "juz", juz: j} })
        picker.playSelected(items)
    }

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
                MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: picker.closed() }
            }
            Text {
                text: "Juz"
                color: "#e8f5ee"
                font.pixelSize: 20
                font.weight: Font.Medium
                Layout.leftMargin: 12
                Layout.fillWidth: true
            }
            Rectangle {
                width: selectLabel.implicitWidth + 24
                height: 32
                radius: 16
                color: selectionMode ? "#0f6e56" : "#173832"
                Text {
                    id: selectLabel
                    anchors.centerIn: parent
                    text: selectionMode ? "Cancel" : "Select"
                    color: "#dff2ea"
                    font.pixelSize: 13
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: { root.sounds.select(); selectionMode = !selectionMode; selectedJuzs = [] }
                }
            }
        }

        GridView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            cellWidth: width / 5
            cellHeight: 84
            model: 30

            delegate: Item {
                width: GridView.view.cellWidth
                height: GridView.view.cellHeight

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 6
                    radius: 14
                    color: picker.selectionMode && picker.isSelected(index + 1) ? "#0f6e56" : "#173832"
                    scale: juzMouse.pressed ? 0.94 : 1.0
                    Behavior on scale { NumberAnimation { duration: 100 } }

                    Text {
                        anchors.centerIn: parent
                        text: index + 1
                        color: "#dff2ea"
                        font.pixelSize: 18
                        font.weight: Font.Medium
                    }

                    Text {
                        visible: picker.selectionMode && picker.isSelected(index + 1)
                        text: "\u2713"
                        color: "#ffffff"
                        font.pixelSize: 12
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: 6
                    }

                    MouseArea {
                        id: juzMouse
                        anchors.fill: parent
                        onClicked: {
                            if (picker.selectionMode) { root.sounds.itemSelecting(); picker.toggleSelected(index + 1) }
                            else picker.picked(index + 1)
                        }
                    }
                }
            }
        }

        Rectangle {
            visible: selectionMode && selectedJuzs.length > 0
            Layout.fillWidth: true
            height: 48
            radius: 12
            color: "#0f6e56"
            Text {
                anchors.centerIn: parent
                text: "Play " + selectedJuzs.length + " selected"
                color: "#fff"
                font.pixelSize: 14
                font.weight: Font.Medium
            }
            MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: picker.confirmSelection() }
        }
    }
}
