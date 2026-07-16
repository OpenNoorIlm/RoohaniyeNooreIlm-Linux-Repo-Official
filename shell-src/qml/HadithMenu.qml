import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15

// Landing screen shown when opening "Hadith" from the home screen -
// mirrors QuranMenu.qml's shape (continue-reading card + tile grid),
// adapted for hadith's book/topic structure instead of surah/juz.
Rectangle {
    id: menu
    anchors.fill: parent
    color: "#10241f"

    property var lastProgress: quranBackend.lastHadithProgress()
    property var books: quranBackend.hadithBookList()

    property bool showTopicPicker: false
    property string topicPickerBook: ""
    property bool showSearch: false
    property var searchResults: []



    // opts: { book, topic, id, selection } - selection is a pre-resolved
    // array of full hadith maps (from hadithsForSelection()), not ids.
    function openReader(opts) {
        root.navHadithBook = opts.book !== undefined ? opts.book : ""
        root.navHadithTopic = opts.topic !== undefined ? opts.topic : ""
        root.navHadithId = opts.id !== undefined ? opts.id : -1
        root.navHadithSelection = opts.selection !== undefined ? opts.selection : []
        root.navigateTo("hadithreader")
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
                MouseArea { anchors.fill: parent; onClicked: root.goBack() }
            }
            Text { text: "Hadith"; color: "#e8f5ee"; font.pixelSize: 22; font.weight: Font.Medium; Layout.leftMargin: 12 }
        }

        // ---- Continue reading ----
        Rectangle {
            visible: lastProgress.id !== undefined
            Layout.fillWidth: true
            height: 76
            radius: 16
            color: "#0f6e56"

            RowLayout {
                anchors.fill: parent
                anchors.margins: 16
                ColumnLayout {
                    spacing: 2
                    Layout.fillWidth: true
                    Text { text: "Continue reading"; color: "#ffffff"; font.pixelSize: 15; font.weight: Font.Medium }
                    Text {
                        text: (lastProgress.bookDisplayName || "") + " \u00b7 #" + (lastProgress.hadithNum || "")
                              + "  \u00b7  " + (lastProgress.topic || "")
                        color: "#bfe9d8"
                        font.pixelSize: 12
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }
                Text { text: "\u2192"; color: "#ffffff"; font.pixelSize: 20 }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: menu.openReader({ book: lastProgress.book, id: lastProgress.id })
            }
        }

        // ---- Book tiles ----
        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: 14
            rowSpacing: 14

            Repeater {
                model: menu.books

                delegate: Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 110
                    radius: 18
                    color: "#173832"
                    scale: bookMouse.pressed ? 0.96 : 1.0
                    Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 4
                        Text { text: "\uD83D\uDCD6"; color: "#7fd6b4"; font.pixelSize: 22 }
                        Item { Layout.fillHeight: true }
                        Text { text: modelData.displayName; color: "#e8f5ee"; font.pixelSize: 16; font.weight: Font.Medium }
                        Text { text: modelData.count + " hadiths"; color: "#8fb3a4"; font.pixelSize: 11 }
                    }

                    MouseArea {
                        id: bookMouse
                        anchors.fill: parent
                        onClicked: {
                            menu.topicPickerBook = modelData.book
                            menu.showTopicPicker = true
                        }
                    }
                }
            }
        }

        // ---- Secondary action tiles ----
        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: 2
            columnSpacing: 14
            rowSpacing: 14

            Repeater {
                model: [
                    { icon: "\uD83D\uDD0D", label: "Search", sub: "Search all hadiths", action: "search" },
                    { icon: "\u21BB", label: "Random", sub: "A random hadith", action: "random" }
                ]

                delegate: Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 90
                    radius: 18
                    color: "#173832"
                    scale: actionMouse.pressed ? 0.96 : 1.0
                    Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 4
                        Text { text: modelData.icon; color: "#7fd6b4"; font.pixelSize: 20 }
                        Item { Layout.fillHeight: true }
                        Text { text: modelData.label; color: "#e8f5ee"; font.pixelSize: 15; font.weight: Font.Medium }
                        Text { text: modelData.sub; color: "#8fb3a4"; font.pixelSize: 11; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                    }

                    MouseArea {
                        id: actionMouse
                        anchors.fill: parent
                        onClicked: {
                            if (modelData.action === "search") {
                                menu.showSearch = true
                            } else if (modelData.action === "random") {
                                var h = quranBackend.randomHadith()
                                if (h.id !== undefined) menu.openReader({ book: h.book, id: h.id })
                            }
                        }
                    }
                }
            }
        }
    }

    Loader {
        active: menu.showTopicPicker
        anchors.fill: parent
        sourceComponent: HadithTopicPicker {
            book: menu.topicPickerBook
            onPicked: {
                menu.showTopicPicker = false
                menu.openReader({ book: book, topic: topic })
            }
            onReadWholeBook: {
                menu.showTopicPicker = false
                menu.openReader({ book: book })
            }
            onSelectionConfirmed: {
                menu.showTopicPicker = false
                var resolved = quranBackend.hadithsForSelection(items)
                menu.openReader({ selection: resolved })
            }
            onClosed: menu.showTopicPicker = false
        }
    }

    // ---- Search overlay ----
    Rectangle {
        visible: menu.showSearch
        anchors.fill: parent
        color: "#10241f"
        z: 60

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
                    MouseArea { anchors.fill: parent; onClicked: { menu.showSearch = false; searchField.text = "" } }
                }
                Text { text: "Search hadiths"; color: "#e8f5ee"; font.pixelSize: 18; font.weight: Font.Medium; Layout.leftMargin: 12 }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 46
                radius: 12
                color: "#173832"
                border.color: "#2f4b43"
                border.width: 1

                TextField {
                    id: searchField
                    anchors.fill: parent
                    anchors.margins: 4
                    color: "#e8f5ee"
                    placeholderText: "Search english/urdu/arabic text\u2026"
                    placeholderTextColor: "#5f8a7b"
                    background: Item {}
                    onTextChanged: menu.searchResults = text.trim().length >= 2 ? quranBackend.searchHadiths(text.trim(), 30) : []
                }
            }

            Text {
                visible: searchField.text.trim().length >= 2 && menu.searchResults.length === 0
                text: "No matches."
                color: "#8fb3a4"
                font.pixelSize: 13
            }

            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 8
                model: menu.searchResults

                delegate: Rectangle {
                    width: ListView.view.width
                    height: resultCol.height + 20
                    radius: 12
                    color: "#173832"
                    scale: resultMouse.pressed ? 0.98 : 1.0
                    Behavior on scale { NumberAnimation { duration: 100 } }

                    ColumnLayout {
                        id: resultCol
                        width: parent.width - 24
                        x: 12; y: 10
                        spacing: 4
                        Text {
                            text: (modelData.bookDisplayName || "") + " \u00b7 #" + (modelData.hadithNum || "") + "  \u00b7  " + (modelData.topic || "")
                            color: "#7fd6b4"
                            font.pixelSize: 11
                        }
                        Text {
                            text: modelData.english || ""
                            color: "#dff2ea"
                            font.pixelSize: 13
                            wrapMode: Text.WordWrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }

                    MouseArea {
                        id: resultMouse
                        anchors.fill: parent
                        onClicked: {
                            menu.showSearch = false
                            menu.openReader({ book: modelData.book, id: modelData.id })
                        }
                    }
                }
            }
        }
    }
}
