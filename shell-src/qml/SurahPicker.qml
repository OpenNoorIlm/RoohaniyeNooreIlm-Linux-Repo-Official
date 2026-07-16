import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15

// Full-screen overlay: pick a surah to jump to. Emits picked(surah, ayah).
Rectangle {
    id: picker
    anchors.fill: parent
    color: "#10241f"
    z: 50

    signal picked(int surah, int ayah)
    signal closed()
    signal playSelected(var items)

    property var allSurahs: quranBackend.surahList()
    property string filterText: ""

    property bool selectionMode: false
    property var selectedSurahs: []

    function isSelected(s) { return selectedSurahs.indexOf(s) !== -1 }
    function toggleSelected(s) {
        var idx = selectedSurahs.indexOf(s)
        var arr = selectedSurahs.slice()
        if (idx === -1) arr.push(s)
        else arr.splice(idx, 1)
        selectedSurahs = arr
    }
    function confirmSelection() {
        var items = selectedSurahs.map(function(s) { return {type: "surah", surah: s} })
        picker.playSelected(items)
    }

    function matches(item) {
        if (filterText.length === 0) return true
        var f = filterText.toLowerCase()
        return item.nameTransliteration.toLowerCase().indexOf(f) !== -1
            || item.nameEnglish.toLowerCase().indexOf(f) !== -1
            || String(item.surah) === f
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
                MouseArea { anchors.fill: parent; onClicked: picker.closed() }
            }
            Text {
                text: "Surahs"
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
                    onClicked: { root.sounds.select(); selectionMode = !selectionMode; selectedSurahs = [] }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 44
            radius: 12
            color: "#173832"

            TextField {
                anchors.fill: parent
                anchors.margins: 4
                placeholderText: "Search surah name or number"
                placeholderTextColor: "#5f8a7b"
                color: "#e8f5ee"
                background: Item {}
                onTextChanged: picker.filterText = text
            }
        }

        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 6
            model: picker.allSurahs

            delegate: Rectangle {
                width: ListView.view.width
                radius: 12
                visible: picker.matches(modelData)
                height: visible ? 60 : 0
                color: picker.selectionMode && picker.isSelected(modelData.surah) ? "#0f6e56" : "#173832"

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 14

                    Rectangle {
                        width: 34; height: 34; radius: 17
                        color: "#0f6e56"
                        Text {
                            anchors.centerIn: parent
                            text: modelData.surah
                            color: "#fff"
                            font.pixelSize: 12
                        }
                    }

                    ColumnLayout {
                        spacing: 2
                        Layout.fillWidth: true
                        Text {
                            text: modelData.nameTransliteration + "  \u00b7  " + modelData.nameEnglish
                            color: "#dff2ea"
                            font.pixelSize: 14
                        }
                        Text {
                            text: modelData.revelationPlace + "  \u00b7  " + modelData.ayahCount + " ayahs"
                            color: "#8fb3a4"
                            font.pixelSize: 11
                        }
                    }

                    Text {
                        text: modelData.nameArabic
                        color: "#7fd6b4"
                        font.pixelSize: 18
                    }

                    Text {
                        visible: picker.selectionMode && picker.isSelected(modelData.surah)
                        text: "\u2713"
                        color: "#ffffff"
                        font.pixelSize: 16
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        if (picker.selectionMode) { root.sounds.itemSelecting(); picker.toggleSelected(modelData.surah) }
                        else picker.picked(modelData.surah, 1)
                    }
                }
            }
        }

        Rectangle {
            visible: selectionMode && selectedSurahs.length > 0
            Layout.fillWidth: true
            height: 48
            radius: 12
            color: "#0f6e56"
            Text {
                anchors.centerIn: parent
                text: "Play " + selectedSurahs.length + " selected"
                color: "#fff"
                font.pixelSize: 14
                font.weight: Font.Medium
            }
            MouseArea { anchors.fill: parent; onClicked: picker.confirmSelection() }
        }
    }
}
