import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15

// Hadith reader - mirrors QuranView.qml's reading-mode shape (continuous
// scroll, translation-visibility toggles, font size, multi-select),
// adapted for hadith's book/topic structure. No audio/reciter step here:
// this db has no hadith recitation audio, so "select items" goes
// straight to a filtered reading list instead of a playback flow.
//
// Three modes, chosen from what Main.qml's nav properties were set to
// when this view was opened (consumed once in Component.onCompleted,
// same one-shot pattern as QuranView's navSurah/navJuz/navPage):
//   "book"      - continuous, keyset-paginated (infinite scroll) browse
//                 of one whole book, via navHadithBook (+ optional
//                 navHadithId to resume mid-book).
//   "topic"     - one chapter/topic of one book, fully loaded (bounded -
//                 at most a few hundred hadiths), via navHadithBook +
//                 navHadithTopic.
//   "selection" - a caller-resolved list of specific hadiths (from
//                 HadithTopicPicker's multi-select or this view's own
//                 in-reader selection), via navHadithSelection.
Rectangle {
    id: view
    anchors.fill: parent
    color: "#10241f"

    property string mode: "book"
    property string book: ""
    property string topic: ""
    property var items: []
    property int lastLoadedId: 0
    property bool loadingMore: false
    property bool reachedEnd: false

    property int currentId: 0

    property bool showEnglish: true
    property bool showUrdu: false
    property bool showArabic: false
    property string fontSizeKey: "medium" // small | medium | large

    property bool showTopicPicker: false
    property bool showSettings: false

    property bool selectionMode: false
    property var selectedIds: []

    function isSelected(id) { return selectedIds.indexOf(id) !== -1 }
    function toggleSelected(id) {
        var idx = selectedIds.indexOf(id)
        var arr = selectedIds.slice()
        if (idx === -1) arr.push(id)
        else arr.splice(idx, 1)
        selectedIds = arr
    }
    function confirmSelection() {
        // No audio step to route through here (unlike Quran's ayah
        // selection, which opens a reciter picker) - just filter this
        // same view down to the chosen hadiths in place.
        var chosen = view.items.filter(function(h) { return selectedIds.indexOf(h.id) !== -1 })
        view.mode = "selection"
        view.items = chosen
        view.selectionMode = false
        view.selectedIds = []
    }

    readonly property int arabicPixelSize: fontSizeKey === "small" ? 18 : (fontSizeKey === "large" ? 26 : 21)
    readonly property int textPixelSize: fontSizeKey === "small" ? 12 : (fontSizeKey === "large" ? 17 : 14)

    property string headerTitle: {
        if (view.mode === "selection") return "Reading list"
        if (view.items.length > 0) return view.items[0].bookDisplayName || ""
        return ""
    }
    property string headerSubtitle: {
        if (view.mode === "selection") return view.items.length + " selected hadiths"
        if (view.mode === "topic") return view.topic + "  \u00b7  " + view.items.length + " hadiths"
        return "Continuous"
    }

    function loadMore() {
        if (view.mode !== "book" || view.loadingMore || view.reachedEnd) return
        view.loadingMore = true
        var batch = quranBackend.hadithsInBook(view.book, view.lastLoadedId, 30)
        if (batch.length === 0) {
            view.reachedEnd = true
        } else {
            view.items = view.items.concat(batch)
            view.lastLoadedId = batch[batch.length - 1].id
        }
        view.loadingMore = false
    }

    function saveCurrentProgress() {
        if (view.mode !== "selection" && view.currentId > 0) {
            quranBackend.saveHadithProgress(view.currentId)
        }
    }

    Component.onCompleted: {
        showEnglish = quranBackend.preference("hadithShowEnglish", true)
        showUrdu = quranBackend.preference("hadithShowUrdu", false)
        showArabic = quranBackend.preference("hadithShowArabic", false)
        fontSizeKey = quranBackend.preference("hadithFontSize", "medium")

        if (root.navHadithSelection.length > 0) {
            view.mode = "selection"
            view.items = root.navHadithSelection
            root.navHadithSelection = []
        } else if (root.navHadithTopic !== "") {
            view.mode = "topic"
            view.book = root.navHadithBook
            view.topic = root.navHadithTopic
            view.items = quranBackend.hadithsByTopic(view.book, view.topic)
            root.navHadithTopic = ""
            root.navHadithBook = ""
        } else if (root.navHadithBook !== "") {
            view.mode = "book"
            view.book = root.navHadithBook
            var startAfter = 0
            if (root.navHadithId > 0) {
                var h = quranBackend.hadithById(root.navHadithId)
                if (h.id !== undefined && h.book === view.book) startAfter = h.id - 1
            }
            root.navHadithBook = ""
            root.navHadithId = -1
            view.items = quranBackend.hadithsInBook(view.book, startAfter, 30)
            if (view.items.length > 0) view.lastLoadedId = view.items[view.items.length - 1].id
        }

        if (view.items.length > 0) view.currentId = view.items[0].id
    }

    Component.onDestruction: saveCurrentProgress()

    function persistPrefs() {
        quranBackend.setPreference("hadithShowEnglish", showEnglish)
        quranBackend.setPreference("hadithShowUrdu", showUrdu)
        quranBackend.setPreference("hadithShowArabic", showArabic)
        quranBackend.setPreference("hadithFontSize", fontSizeKey)
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 14

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Text {
                text: "\u2190"
                color: "#7fd6b4"
                font.pixelSize: 20
                MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: { saveCurrentProgress(); root.goBack() } }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Text {
                    text: view.headerTitle
                    color: "#e8f5ee"
                    font.pixelSize: 16
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                Text {
                    text: view.headerSubtitle
                    color: "#8fb3a4"
                    font.pixelSize: 11
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }

            Rectangle {
                visible: view.mode !== "selection" && view.book !== ""
                width: 44; height: 44; radius: 22
                color: "#173832"
                Text { anchors.centerIn: parent; text: "\u2637"; color: "#7fd6b4"; font.pixelSize: 15 }
                MouseArea { anchors.fill: parent; onClicked: showTopicPicker = true }
            }

            Rectangle {
                width: 44; height: 44; radius: 22
                color: selectionMode ? "#0f6e56" : "#173832"
                Text { anchors.centerIn: parent; text: "\u2611"; color: selectionMode ? "#fff" : "#7fd6b4"; font.pixelSize: 14 }
                MouseArea {
                    anchors.fill: parent
                    onClicked: { selectionMode = !selectionMode; selectedIds = [] }
                }
            }

            Rectangle {
                width: 44; height: 44; radius: 22
                color: "#173832"
                Text { anchors.centerIn: parent; text: "\u2699"; color: "#7fd6b4"; font.pixelSize: 15 }
                MouseArea { anchors.fill: parent; onClicked: showSettings = true }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 16
            color: "#173832"
            clip: true

            ListView {
                id: hadithList
                anchors.fill: parent
                anchors.margins: 8
                clip: true
                spacing: 4
                model: view.items

                onContentYChanged: {
                    if (view.items.length === 0) return
                    var idx = indexAt(width / 2, contentY + 12)
                    if (idx >= 0 && idx < view.items.length) {
                        view.currentId = view.items[idx].id
                    }
                }

                onAtYEndChanged: if (atYEnd) view.loadMore()

                footer: Item {
                    width: hadithList.width
                    height: (view.mode === "book" && view.loadingMore) ? 40 : 0
                    Text {
                        anchors.centerIn: parent
                        visible: view.mode === "book" && view.loadingMore
                        text: "Loading more\u2026"
                        color: "#8fb3a4"
                        font.pixelSize: 12
                    }
                }

                delegate: Rectangle {
                    width: hadithList.width
                    height: delegateCol.height + 24
                    radius: 12
                    color: (view.selectionMode && view.isSelected(modelData.id)) ? "#1d4a40" : "transparent"

                    MouseArea {
                        anchors.fill: parent
                        z: -1
                        enabled: view.selectionMode
                        onClicked: view.toggleSelected(modelData.id)
                    }

                    ColumnLayout {
                        id: delegateCol
                        width: parent.width - 24
                        x: 12; y: 12
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "#" + (modelData.hadithNum || "") + "  \u00b7  " + (modelData.topic || "")
                                color: "#7fd6b4"
                                font.pixelSize: 11
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            Text {
                                visible: view.selectionMode
                                text: view.isSelected(modelData.id) ? "\u2611" : "\u2610"
                                color: view.isSelected(modelData.id) ? "#7fd6b4" : "#8fb3a4"
                                font.pixelSize: 16
                            }
                        }

                        Text {
                            visible: showEnglish
                            text: modelData.english || ""
                            color: "#dff2ea"
                            font.pixelSize: textPixelSize
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                        Text {
                            visible: showUrdu
                            text: modelData.urdu || ""
                            color: "#bfe9d8"
                            font.pixelSize: textPixelSize
                            horizontalAlignment: Text.AlignRight
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                        Text {
                            visible: showArabic
                            text: modelData.arabic || ""
                            color: "#ffffff"
                            font.pixelSize: arabicPixelSize
                            horizontalAlignment: Text.AlignRight
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                    }
                }
            }
        }

        // ---- Selection confirm bar ----
        Rectangle {
            visible: selectionMode && selectedIds.length > 0
            Layout.fillWidth: true
            height: 48
            radius: 12
            color: "#0f6e56"
            Text {
                anchors.centerIn: parent
                text: "Show " + selectedIds.length + " selected hadiths"
                color: "#fff"
                font.pixelSize: 14
                font.weight: Font.Medium
            }
            MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: view.confirmSelection() }
        }
    }

    // ---- Overlays ----
    Loader {
        active: view.showTopicPicker
        anchors.fill: parent
        sourceComponent: HadithTopicPicker {
            book: view.book
            onPicked: {
                view.showTopicPicker = false
                view.mode = "topic"
                view.topic = topic
                view.items = quranBackend.hadithsByTopic(book, topic)
                if (view.items.length > 0) view.currentId = view.items[0].id
            }
            onReadWholeBook: {
                view.showTopicPicker = false
                view.mode = "book"
                view.topic = ""
                view.reachedEnd = false
                view.items = quranBackend.hadithsInBook(book, 0, 30)
                view.lastLoadedId = view.items.length > 0 ? view.items[view.items.length - 1].id : 0
                if (view.items.length > 0) view.currentId = view.items[0].id
            }
            onSelectionConfirmed: {
                view.showTopicPicker = false
                view.mode = "selection"
                view.items = quranBackend.hadithsForSelection(items)
            }
            onClosed: view.showTopicPicker = false
        }
    }

    // Reader settings panel
    Rectangle {
        visible: showSettings
        anchors.fill: parent
        color: "#00000099"
        z: 60

        MouseArea { anchors.fill: parent; onClicked: { showSettings = false; persistPrefs() } }

        Rectangle {
            width: Math.min(360, parent.width - 40)
            anchors.centerIn: parent
            radius: 18
            color: "#173832"
            height: settingsCol.height + 32

            MouseArea { anchors.fill: parent } // swallow clicks so outer overlay doesn't close

            ColumnLayout {
                id: settingsCol
                x: 16; y: 16
                width: parent.width - 32
                spacing: 18

                Text { text: "Reading settings"; color: "#e8f5ee"; font.pixelSize: 17; font.weight: Font.Medium }

                ColumnLayout {
                    spacing: 8
                    Text { text: "Text shown"; color: "#8fb3a4"; font.pixelSize: 12 }

                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: "English"; color: "#dff2ea"; font.pixelSize: 13; Layout.fillWidth: true }
                        Switch { checked: showEnglish; onToggled: showEnglish = checked }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: "Urdu"; color: "#dff2ea"; font.pixelSize: 13; Layout.fillWidth: true }
                        Switch { checked: showUrdu; onToggled: showUrdu = checked }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: "Arabic"; color: "#dff2ea"; font.pixelSize: 13; Layout.fillWidth: true }
                        Switch { checked: showArabic; onToggled: showArabic = checked }
                    }
                }

                ColumnLayout {
                    spacing: 8
                    Text { text: "Text size"; color: "#8fb3a4"; font.pixelSize: 12 }
                    RowLayout {
                        spacing: 8
                        Layout.fillWidth: true
                        Repeater {
                            model: [ {k:"small",l:"A"}, {k:"medium",l:"A"}, {k:"large",l:"A"} ]
                            delegate: Rectangle {
                                Layout.fillWidth: true; height: 44; radius: 10
                                color: fontSizeKey === modelData.k ? "#0f6e56" : "#10241f"
                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.l
                                    color: "#fff"
                                    font.pixelSize: modelData.k === "small" ? 13 : (modelData.k === "large" ? 20 : 16)
                                }
                                MouseArea { anchors.fill: parent; onClicked: fontSizeKey = modelData.k }
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 40
                    radius: 10
                    color: "#0f6e56"
                    Text { anchors.centerIn: parent; text: "Done"; color: "#fff"; font.pixelSize: 13 }
                    MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: { showSettings = false; persistPrefs() } }
                }
            }
        }
    }
}
