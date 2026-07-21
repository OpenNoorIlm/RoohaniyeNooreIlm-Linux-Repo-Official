import QtQuick 2.15
import QtQuick.Layouts 1.15

// Full-screen overlay: pick a topic (chapter) within one hadith book to
// jump to. Emits picked(book, topic). Mirrors JuzPicker.qml's shape:
// a "Select" toggle lets you multi-select topics, then "Read N selected"
// emits selectionConfirmed(items) - an array of
// {type:"topic", book:..., topic:...} objects, expanded and de-duped by
// QuranBackend::hadithsForSelection() on the caller's side (same
// division of labor as JuzPicker -> versesForSelection()). Unlike the
// Quran pickers there's no reciter step after confirming - hadith has no
// recitation audio in this db, so confirming goes straight to a filtered
// reading list.
Rectangle {
    id: picker
    anchors.fill: parent
    color: "#10241f"
    z: 50

    property string book: ""
    property var topics: book !== "" ? quranBackend.hadithTopics(book) : []
    property string bookDisplayName: {
        var found = quranBackend.hadithBookList().filter(function(b) { return b.book === picker.book })
        return found.length > 0 ? found[0].displayName : "Topics"
    }

    signal picked(string book, string topic)
    signal readWholeBook(string book)
    signal selectionConfirmed(var items)
    signal closed()

    property bool selectionMode: false
    property var selectedTopics: []

    function isSelected(t) { return selectedTopics.indexOf(t) !== -1 }
    function toggleSelected(t) {
        var idx = selectedTopics.indexOf(t)
        var arr = selectedTopics.slice()
        if (idx === -1) arr.push(t)
        else arr.splice(idx, 1)
        selectedTopics = arr
    }
    function confirmSelection() {
        var items = selectedTopics.map(function(t) { return {type: "topic", book: picker.book, topic: t} })
        picker.selectionConfirmed(items)
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
                MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: { root.sounds.buttonClick(); picker.closed() } }
            }
            Text {
                text: picker.bookDisplayName
                color: "#e8f5ee"
                font.pixelSize: 20
                font.weight: Font.Medium
                Layout.leftMargin: 12
                Layout.fillWidth: true
                elide: Text.ElideRight
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
                    onClicked: { root.sounds.select(); selectionMode = !selectionMode; selectedTopics = [] }
                }
            }
        }

        // ---- Read the whole book, start to finish ----
        Rectangle {
            visible: !selectionMode
            Layout.fillWidth: true
            height: 56
            radius: 14
            color: "#0f6e56"
            RowLayout {
                anchors.fill: parent
                anchors.margins: 14
                Text { text: "\uD83D\uDCD6"; color: "#fff"; font.pixelSize: 16 }
                Text { text: "Read this book, start to finish"; color: "#fff"; font.pixelSize: 14; font.weight: Font.Medium; Layout.leftMargin: 8; Layout.fillWidth: true }
                Text { text: "\u2192"; color: "#fff"; font.pixelSize: 16 }
            }
            MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: { root.sounds.buttonClick(); picker.readWholeBook(picker.book) } }
        }

        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 8
            model: picker.topics

            delegate: Rectangle {
                width: ListView.view.width
                height: 56
                radius: 14
                color: picker.selectionMode && picker.isSelected(modelData.topic) ? "#0f6e56" : "#173832"
                scale: topicMouse.pressed ? 0.98 : 1.0
                Behavior on scale { NumberAnimation { duration: 100 } }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 10

                    Text {
                        visible: picker.selectionMode
                        text: picker.isSelected(modelData.topic) ? "\u2611" : "\u2610"
                        color: picker.isSelected(modelData.topic) ? "#ffffff" : "#8fb3a4"
                        font.pixelSize: 16
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        Text { text: modelData.topic; color: "#dff2ea"; font.pixelSize: 14; font.weight: Font.Medium; elide: Text.ElideRight; Layout.fillWidth: true }
                        Text { text: modelData.count + " hadiths"; color: "#8fb3a4"; font.pixelSize: 11 }
                    }
                }

                MouseArea {
                    id: topicMouse
                    anchors.fill: parent
                    onClicked: {
                        if (picker.selectionMode) { root.sounds.itemSelecting(); picker.toggleSelected(modelData.topic) }
                        else picker.picked(picker.book, modelData.topic)
                    }
                }
            }
        }

        Rectangle {
            visible: selectionMode && selectedTopics.length > 0
            Layout.fillWidth: true
            height: 48
            radius: 12
            color: "#0f6e56"
            Text {
                anchors.centerIn: parent
                text: "Read " + selectedTopics.length + " selected topics"
                color: "#fff"
                font.pixelSize: 14
                font.weight: Font.Medium
            }
            MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: { root.sounds.buttonClick(); picker.confirmSelection() } }
        }
    }
}
