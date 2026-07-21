import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15

// Landing screen shown when opening "Quran" from the home screen.
// Tiles: Hafizi (mushaf view), Juz, Surah, Go to Page, About Quran, Random.
// Plus a "Continue reading" card up top when there's saved progress.
Rectangle {
    id: menu
    anchors.fill: parent
    color: "#10241f"

    property var lastProgress: quranBackend.lastProgress()
    property bool showJuzPicker: false
    property bool showSurahPicker: false
    property bool showGoToPage: false

    // ---- "Select items, then pick a reciter" playback, mirroring
    // QuranView.qml's flow. JuzPicker/SurahPicker emit playSelected(items)
    // when the user confirms a multi-select; that's stashed here and a
    // ReciterPicker overlay opens on top of this menu. Picking a reciter
    // expands the selection into a verse playlist and starts it via
    // AudioBackend (a global context property, so playback keeps going
    // across the screen navigation below), then drops into the reader so
    // the mini audio bar is visible.
    property var pendingSelection: []
    property bool showReciterPicker: false

    function startSelectionPlayback(reciterId) {
        var verses = quranBackend.versesForSelection(pendingSelection)
        if (verses.length === 0) return
        quranBackend.setPreference("reciterId", reciterId)
        audioBackend.playSelection(verses, reciterId)
        pendingSelection = []
        showReciterPicker = false
        menu.openReader({ surah: verses[0].surah, ayah: verses[0].ayah, layoutMode: "reading" })
    }

    function openReader(opts) {
        // opts: { surah, ayah, page, juz, layoutMode }
        root.navSurah = opts.surah !== undefined ? opts.surah : -1
        root.navAyah = opts.ayah !== undefined ? opts.ayah : -1
        root.navPage = opts.page !== undefined ? opts.page : -1
        root.navJuz = opts.juz !== undefined ? opts.juz : -1
        root.navLayoutMode = opts.layoutMode !== undefined ? opts.layoutMode : ""
        root.navigateTo("quranreader")
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
                MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: { root.sounds.buttonClick(); root.goBack() } }
            }
            Text { text: "Quran"; color: "#e8f5ee"; font.pixelSize: 22; font.weight: Font.Medium; Layout.leftMargin: 12 }
        }

        // ---- Continue reading ----
        Rectangle {
            visible: lastProgress.surah !== undefined
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
                        text: "Surah " + lastProgress.surah + ", Ayah " + lastProgress.ayah
                        color: "#bfe9d8"
                        font.pixelSize: 12
                    }
                }
                Text { text: "\u2192"; color: "#ffffff"; font.pixelSize: 20 }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: { root.sounds.buttonClick(); menu.openReader({ surah: lastProgress.surah, ayah: lastProgress.ayah, layoutMode: "reading" }) }
            }
        }

        // ---- Main tile grid ----
        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: 2
            columnSpacing: 14
            rowSpacing: 14

            Repeater {
                model: [
                    { icon: "\u25A6", label: "Hafizi", sub: "Dense Arabic mushaf view", action: "hafizi" },
                    { icon: "\uD83D\uDCD3", label: "Quran Mushaf", sub: "Scanned page-by-page mushaf editions", action: "mushafgallery" },
                    { icon: "\u2637", label: "Juz", sub: "Browse by juz (1\u201330)", action: "juz" },
                    { icon: "\uD83D\uDCD6", label: "Surah", sub: "Browse all 114 surahs", action: "surah" },
                    { icon: "#", label: "Go to Page", sub: "Jump to a mushaf page", action: "page" },
                    { icon: "\u2139", label: "About Quran", sub: "Structure & stats", action: "about" },
                    { icon: "\u21BB", label: "Random", sub: "A random ayah", action: "random" }
                ]

                delegate: Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 110
                    radius: 18
                    color: "#173832"
                    scale: tileMouse.pressed ? 0.96 : 1.0
                    Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 4
                        Text { text: modelData.icon; color: "#7fd6b4"; font.pixelSize: 22 }
                        Item { Layout.fillHeight: true }
                        Text { text: modelData.label; color: "#e8f5ee"; font.pixelSize: 16; font.weight: Font.Medium }
                        Text { text: modelData.sub; color: "#8fb3a4"; font.pixelSize: 11; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                    }

                    MouseArea {
                        id: tileMouse
                        anchors.fill: parent
                        onClicked: { root.sounds.buttonClick();
                            switch (modelData.action) {
                            case "hafizi":
                                menu.openReader({ page: 1, layoutMode: "mushaf" })
                                break
                            case "mushafgallery":
                                root.navigateTo("mushafgallery")
                                break
                            case "juz":
                                menu.showJuzPicker = true
                                break
                            case "surah":
                                menu.showSurahPicker = true
                                break
                            case "page":
                                menu.showGoToPage = true
                                break
                            case "about":
                                root.navigateTo("aboutquran")
                                break
                            case "random":
                                var v = quranBackend.randomVerse()
                                menu.openReader({ surah: v.surah, ayah: v.ayah, layoutMode: "reading" })
                                break
                            }
                        }
                    }
                }
            }
        }
    }

    Loader {
        active: menu.showJuzPicker
        anchors.fill: parent
        sourceComponent: JuzPicker {
            onPicked: {
                menu.showJuzPicker = false
                menu.openReader({ juz: juz, layoutMode: "mushaf" })
            }
            onClosed: menu.showJuzPicker = false
            onPlaySelected: {
                menu.pendingSelection = items
                menu.showJuzPicker = false
                menu.showReciterPicker = true
            }
        }
    }

    Loader {
        active: menu.showSurahPicker
        anchors.fill: parent
        sourceComponent: SurahPicker {
            onPicked: {
                menu.showSurahPicker = false
                menu.openReader({ surah: surah, ayah: ayah, layoutMode: "reading" })
            }
            onClosed: menu.showSurahPicker = false
            onPlaySelected: {
                menu.pendingSelection = items
                menu.showSurahPicker = false
                menu.showReciterPicker = true
            }
        }
    }

    Loader {
        active: menu.showReciterPicker
        anchors.fill: parent
        sourceComponent: ReciterPicker {
            currentReciterId: quranBackend.preference("reciterId", "")
            onPicked: menu.startSelectionPlayback(reciterId)
            onClosed: { menu.pendingSelection = []; menu.showReciterPicker = false }
        }
    }

    // ---- Go to page dialog ----
    Rectangle {
        visible: menu.showGoToPage
        anchors.fill: parent
        color: "#00000099"
        z: 60

        MouseArea { anchors.fill: parent; onClicked: { root.sounds.buttonClick(); menu.showGoToPage = false } }

        Rectangle {
            width: Math.min(320, parent.width - 40)
            anchors.centerIn: parent
            radius: 18
            color: "#173832"
            height: pageCol.height + 32

            MouseArea { anchors.fill: parent }

            ColumnLayout {
                id: pageCol
                x: 16; y: 16
                width: parent.width - 32
                spacing: 14

                Text { text: "Go to page"; color: "#e8f5ee"; font.pixelSize: 17; font.weight: Font.Medium }
                Text { text: "1\u2013" + quranBackend.totalPages(); color: "#8fb3a4"; font.pixelSize: 12 }

                Rectangle {
                    Layout.fillWidth: true
                    height: 44
                    radius: 10
                    color: "#10241f"
                    border.color: "#2f4b43"
                    border.width: 1

                    TextField {
                        id: pageField
                        anchors.fill: parent
                        anchors.margins: 4
                        horizontalAlignment: Text.AlignHCenter
                        color: "#e8f5ee"
                        placeholderText: "Page number"
                        placeholderTextColor: "#5f8a7b"
                        validator: IntValidator { bottom: 1; top: quranBackend.totalPages() }
                        background: Item {}
                        Component.onCompleted: forceActiveFocus()
                        onAccepted: goButton.clicked()
                    }
                }

                Rectangle {
                    id: goButton
                    Layout.fillWidth: true
                    height: 44
                    radius: 10
                    color: "#0f6e56"
                    Text { anchors.centerIn: parent; text: "Go"; color: "#fff"; font.pixelSize: 14 }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: { root.sounds.buttonClick();
                            var p = parseInt(pageField.text)
                            if (!isNaN(p) && p >= 1 && p <= quranBackend.totalPages()) {
                                menu.showGoToPage = false
                                menu.openReader({ page: p, layoutMode: "mushaf" })
                            }
                        }
                    }
                }
            }
        }
    }
}
