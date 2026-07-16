import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15

Rectangle {
    id: view
    anchors.fill: parent
    color: "#10241f"

    // ---- Navigation state ----
    property int currentSurah: 1
    property int currentAyah: 1
    property int currentPage: 1

    // "reading" = per-surah scroll with translations. "mushaf" = Hafizi-style
    // dense Arabic-only page view, paginated like a physical mushaf.
    property string layoutMode: "reading"

    property bool showEnglish: true
    property bool showUrdu: false
    property bool showTafsir: false
    property string fontSizeKey: "medium" // small | medium | large

    property bool showSurahPicker: false
    property bool showJuzPicker: false
    property bool showSettings: false
    property bool showAbout: false

    // ---- Audio playback state ----
    property var reciterList: []
    property string selectedReciterId: ""
    property bool showReciterPicker: false
    property string audioErrorText: ""

    // ---- Multi-select playback ("select juz/surah/ayah, then reciter") ----
    // Ayah-level selection happens right here in the reading list; juz-
    // and surah-level selection happen inside JuzPicker/SurahPicker (each
    // has its own "Select" toggle) and arrive via their playSelected
    // signal. Either path stashes its picks into pendingSelection and
    // opens the reciter picker in "for selection" mode; picking a reciter
    // there expands the selection into a verse playlist and starts it.
    property bool ayahSelectionMode: false
    property var selectedAyahs: []
    property var pendingSelection: []
    property bool reciterPickerForSelection: false

    function isAyahSelected(surah, ayah) {
        for (var i = 0; i < selectedAyahs.length; i++) {
            if (selectedAyahs[i].surah === surah && selectedAyahs[i].ayah === ayah) return true
        }
        return false
    }
    function toggleAyahSelected(surah, ayah) {
        var arr = selectedAyahs.slice()
        for (var i = 0; i < arr.length; i++) {
            if (arr[i].surah === surah && arr[i].ayah === ayah) { arr.splice(i, 1); selectedAyahs = arr; return }
        }
        arr.push({surah: surah, ayah: ayah})
        selectedAyahs = arr
    }
    function confirmAyahSelection() {
        pendingSelection = selectedAyahs.map(function(a) { return {type: "ayah", surah: a.surah, ayah: a.ayah} })
        reciterPickerForSelection = true
        showReciterPicker = true
    }
    function startSelectionPlayback(reciterId) {
        var verses = quranBackend.versesForSelection(pendingSelection)
        if (verses.length === 0) return
        selectedReciterId = reciterId
        quranBackend.setPreference("reciterId", reciterId)
        audioSessionStarted = true
        audioBackend.playSelection(verses, reciterId)
        ayahSelectionMode = false
        selectedAyahs = []
        pendingSelection = []
    }

    // The mini audio bar shows once a playback session has started this
    // view instance (i.e. a verse has actually been loaded into the
    // player), and stays visible - including when paused/stopped - so the
    // user has a persistent way to resume/change reciter/change loop mode
    // without re-finding the verse they were on.
    property bool audioSessionStarted: false

    function isCurrentAudioVerse(surah, ayah) {
        return audioBackend.currentSurah === surah && audioBackend.currentAyah === ayah
                && audioBackend.currentReciterId === selectedReciterId
    }

    function toggleVersePlayback(surah, ayah) {
        audioSessionStarted = true
        if (isCurrentAudioVerse(surah, ayah)) {
            if (audioBackend.playing) {
                audioBackend.pause()
            } else {
                audioBackend.resume()
            }
        } else {
            audioBackend.playVerse(surah, ayah, selectedReciterId)
        }
    }

    function cycleLoopMode() {
        // Off -> RepeatVerse -> RepeatRange -> Off
        audioBackend.setLoopMode((audioBackend.loopMode + 1) % 3)
    }

    function loopModeLabel(mode) {
        if (mode === 1) return "Repeat verse"
        if (mode === 2) return "Repeat range"
        return "No repeat"
    }

    readonly property int arabicPixelSize: fontSizeKey === "small" ? 20 : (fontSizeKey === "large" ? 32 : 26)
    readonly property int translationPixelSize: fontSizeKey === "small" ? 12 : (fontSizeKey === "large" ? 17 : 14)

    property var surahMeta: quranBackend.surahInfo(currentSurah)
    property var surahVerses: []
    property var pageVerses: []

    function loadSurah() {
        surahMeta = quranBackend.surahInfo(currentSurah)
        surahVerses = quranBackend.versesInSurah(currentSurah)
    }

    function loadPage() {
        pageVerses = quranBackend.versesInPage(currentPage)
    }

    function goToSurah(surah, ayah) {
        currentSurah = surah
        currentAyah = ayah
        layoutMode = "reading"
        loadSurah()
        Qt.callLater(function() {
            var idx = ayah - 1
            if (idx >= 0 && idx < surahVerses.length) verseList.positionViewAtIndex(idx, ListView.Beginning)
        })
    }

    function goToJuz(juz) {
        var verses = quranBackend.versesInJuz(juz)
        if (verses.length > 0) {
            currentPage = verses[0].page
            layoutMode = "mushaf"
            loadPage()
        }
    }

    function saveCurrentProgress() {
        quranBackend.saveProgress(currentSurah, currentAyah)
    }

    Component.onCompleted: {
        showEnglish = quranBackend.preference("showEnglish", true)
        showUrdu = quranBackend.preference("showUrdu", false)
        showTafsir = quranBackend.preference("showTafsir", false)
        fontSizeKey = quranBackend.preference("fontSize", "medium")
        layoutMode = quranBackend.preference("layoutMode", "reading")

        reciterList = quranBackend.reciterList()
        selectedReciterId = quranBackend.preference("reciterId",
            reciterList.length > 0 ? reciterList[0].id : "")

        if (root.navLayoutMode !== "") {
            layoutMode = root.navLayoutMode
            root.navLayoutMode = ""
        }

        // One-shot nav targets, checked in priority order: juz, then page,
        // then surah/ayah, then fall back to last saved progress. Only one
        // of these is ever set at a time by QuranMenu.qml/SurahPicker/
        // JuzPicker, but juz/page take priority over navSurah since they
        // imply a specific mushaf page that a surah/ayah lookup shouldn't
        // silently override further down.
        var explicitPage = false
        if (root.navJuz > 0) {
            var jVerses = quranBackend.versesInJuz(root.navJuz)
            if (jVerses.length > 0) {
                currentSurah = jVerses[0].surah
                currentAyah = jVerses[0].ayah
                currentPage = jVerses[0].page
                explicitPage = true
            }
            root.navJuz = -1
        } else if (root.navPage > 0) {
            currentPage = root.navPage
            var pVerses = quranBackend.versesInPage(root.navPage)
            if (pVerses.length > 0) {
                currentSurah = pVerses[0].surah
                currentAyah = pVerses[0].ayah
            }
            explicitPage = true
            root.navPage = -1
        } else if (root.navSurah > 0) {
            currentSurah = root.navSurah
            currentAyah = root.navAyah > 0 ? root.navAyah : 1
            root.navSurah = -1
            root.navAyah = -1
        } else {
            var last = quranBackend.lastProgress()
            currentSurah = last.surah
            currentAyah = last.ayah
        }

        loadSurah()
        if (!explicitPage) {
            var v = quranBackend.verse(currentSurah, currentAyah)
            currentPage = v.page || 1
        }
        if (layoutMode === "mushaf") loadPage()

        Qt.callLater(function() {
            var idx = currentAyah - 1
            if (idx >= 0 && idx < surahVerses.length) verseList.positionViewAtIndex(idx, ListView.Beginning)
        })
    }

    Connections {
        target: audioBackend
        function onPlaybackError(message) {
            audioErrorText = message
            errorClearTimer.restart()
        }
    }

    Timer {
        id: errorClearTimer
        interval: 4000
        onTriggered: audioErrorText = ""
    }

    Component.onDestruction: saveCurrentProgress()

    function persistPrefs() {
        quranBackend.setPreference("showEnglish", showEnglish)
        quranBackend.setPreference("showUrdu", showUrdu)
        quranBackend.setPreference("showTafsir", showTafsir)
        quranBackend.setPreference("fontSize", fontSizeKey)
        quranBackend.setPreference("layoutMode", layoutMode)
    }

    // ---- Top bar + body ----
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
                MouseArea { anchors.fill: parent; onClicked: { saveCurrentProgress(); audioBackend.stop(); root.goBack() } }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 40
                color: "transparent"

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0
                    Text {
                        text: (surahMeta.nameTransliteration || "") + " \u00b7 " + (surahMeta.nameEnglish || "")
                        color: "#e8f5ee"
                        font.pixelSize: 16
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    Text {
                        text: layoutMode === "mushaf"
                            ? ("Page " + currentPage + " of " + quranBackend.totalPages())
                            : ("Ayah " + currentAyah + " of " + (surahMeta.ayahCount || "?"))
                        color: "#8fb3a4"
                        font.pixelSize: 11
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: showSurahPicker = true
                }
            }

            Rectangle {
                width: 36; height: 36; radius: 18
                color: "#173832"
                Text { anchors.centerIn: parent; text: "\u2637"; color: "#7fd6b4"; font.pixelSize: 15 }
                MouseArea { anchors.fill: parent; onClicked: showJuzPicker = true }
            }

            Rectangle {
                visible: layoutMode === "reading" && selectedReciterId !== ""
                width: 36; height: 36; radius: 18
                color: ayahSelectionMode ? "#0f6e56" : "#173832"
                Text { anchors.centerIn: parent; text: "\u2611"; color: ayahSelectionMode ? "#fff" : "#7fd6b4"; font.pixelSize: 14 }
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        ayahSelectionMode = !ayahSelectionMode
                        selectedAyahs = []
                    }
                }
            }

            Rectangle {
                width: 36; height: 36; radius: 18
                color: "#173832"
                Text { anchors.centerIn: parent; text: "\u2699"; color: "#7fd6b4"; font.pixelSize: 15 }
                MouseArea { anchors.fill: parent; onClicked: showSettings = true }
            }
        }

        // ---- READING MODE ----
        Rectangle {
            visible: layoutMode === "reading"
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 16
            color: "#173832"
            clip: true

            ListView {
                id: verseList
                anchors.fill: parent
                anchors.margins: 8
                clip: true
                spacing: 4
                model: surahVerses

                header: Rectangle {
                    width: verseList.width
                    height: aboutCol.height + 20
                    radius: 12
                    color: "#10241f"

                    ColumnLayout {
                        id: aboutCol
                        width: parent.width - 20
                        x: 10; y: 10
                        spacing: 4
                        Text {
                            text: (surahMeta.revelationPlace || "") + "  \u00b7  " + (surahMeta.ayahCount || 0) + " ayahs  \u00b7  " + (surahMeta.nameArabic || "")
                            color: "#7fd6b4"
                            font.pixelSize: 12
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                    }
                }

                onContentYChanged: {
                    if (surahVerses.length === 0) return
                    var idx = indexAt(width / 2, contentY + 12)
                    if (idx >= 0 && idx < surahVerses.length) {
                        currentAyah = surahVerses[idx].ayah
                    }
                }

                delegate: Rectangle {
                    width: verseList.width
                    height: delegateCol.height + 24
                    radius: 12
                    color: ayahSelectionMode && view.isAyahSelected(modelData.surah, modelData.ayah)
                        ? "#1d4a40"
                        : (modelData.ayah === currentAyah ? "#1d4a40" : "transparent")

                    MouseArea {
                        anchors.fill: parent
                        z: -1
                        enabled: ayahSelectionMode
                        onClicked: { root.sounds.itemSelecting(); view.toggleAyahSelected(modelData.surah, modelData.ayah) }
                    }

                    ColumnLayout {
                        id: delegateCol
                        width: parent.width - 24
                        x: 12; y: 12
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            Rectangle {
                                width: 22; height: 22; radius: 11
                                color: "#0f6e56"
                                Text { anchors.centerIn: parent; text: modelData.ayah; color: "#fff"; font.pixelSize: 10 }
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                visible: ayahSelectionMode
                                text: view.isAyahSelected(modelData.surah, modelData.ayah) ? "\u2611" : "\u2610"
                                color: view.isAyahSelected(modelData.surah, modelData.ayah) ? "#7fd6b4" : "#8fb3a4"
                                font.pixelSize: 16
                            }
                            Rectangle {
                                visible: !ayahSelectionMode && selectedReciterId !== ""
                                width: 34; height: 34; radius: 17
                                color: view.isCurrentAudioVerse(modelData.surah, modelData.ayah) ? "#0f6e56" : "#20463c"
                                Text {
                                    anchors.centerIn: parent
                                    text: view.isCurrentAudioVerse(modelData.surah, modelData.ayah) && audioBackend.playing ? "\u23F8" : "\u25B6"
                                    color: "#dff2ea"
                                    font.pixelSize: 12
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: view.toggleVersePlayback(modelData.surah, modelData.ayah)
                                }
                            }
                        }

                        Text {
                            text: modelData.arabic
                            color: "#ffffff"
                            font.pixelSize: arabicPixelSize
                            horizontalAlignment: Text.AlignRight
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                        }

                        Rectangle {
                            visible: showEnglish || showUrdu || showTafsir
                            Layout.fillWidth: true
                            height: 1
                            color: "#2f4b43"
                        }

                        Text {
                            visible: showEnglish
                            text: modelData.english || ""
                            color: "#bfe9d8"
                            font.pixelSize: translationPixelSize
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                        Text {
                            visible: showUrdu
                            text: modelData.urdu || ""
                            color: "#bfe9d8"
                            font.pixelSize: translationPixelSize
                            horizontalAlignment: Text.AlignRight
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                        Text {
                            visible: showTafsir
                            text: modelData.tafsir || ""
                            color: "#9fc9b8"
                            font.pixelSize: translationPixelSize
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                    }
                }
            }
        }

        // ---- Ayah selection confirm bar (reading mode "Select" tool) ----
        Rectangle {
            visible: ayahSelectionMode && selectedAyahs.length > 0
            Layout.fillWidth: true
            height: 48
            radius: 12
            color: "#0f6e56"
            Text {
                anchors.centerIn: parent
                text: "Play " + selectedAyahs.length + " selected ayahs"
                color: "#fff"
                font.pixelSize: 14
                font.weight: Font.Medium
            }
            MouseArea { anchors.fill: parent; onClicked: view.confirmAyahSelection() }
        }

        // ---- MUSHAF (Hafizi) MODE: dense Arabic-only, paginated ----
        Rectangle {
            visible: layoutMode === "mushaf"
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 16
            color: "#173832"
            clip: true

            Flickable {
                anchors.fill: parent
                anchors.margins: 20
                contentHeight: pageFlow.height
                clip: true

                Flow {
                    id: pageFlow
                    width: parent.width
                    spacing: 10
                    layoutDirection: Qt.RightToLeft

                    Repeater {
                        model: pageVerses
                        delegate: Row {
                            spacing: 6
                            layoutDirection: Qt.RightToLeft

                            Text {
                                text: modelData.arabic
                                color: "#ffffff"
                                font.pixelSize: arabicPixelSize - 2
                            }

                            Rectangle {
                                width: 20; height: 20; radius: 10
                                y: 4
                                color: "#0f6e56"
                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.ayah
                                    color: "#fff"
                                    font.pixelSize: 9
                                }
                            }
                        }
                    }
                }
            }
        }

        RowLayout {
            visible: layoutMode === "mushaf"
            Layout.fillWidth: true
            spacing: 12

            Rectangle {
                Layout.fillWidth: true
                height: 44
                radius: 10
                color: "#0f6e56"
                Text { anchors.centerIn: parent; text: "\u2190 Previous page"; color: "#fff"; font.pixelSize: 13 }
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        if (currentPage > 1) { currentPage -= 1; loadPage() }
                    }
                }
            }

            Rectangle {
                width: 100
                height: 44
                radius: 10
                color: "#173832"
                border.color: "#2f4b43"
                border.width: 1

                TextField {
                    id: pageJumpField
                    anchors.fill: parent
                    anchors.margins: 4
                    horizontalAlignment: Text.AlignHCenter
                    color: "#e8f5ee"
                    placeholderText: "Page"
                    placeholderTextColor: "#5f8a7b"
                    validator: IntValidator { bottom: 1; top: quranBackend.totalPages() }
                    background: Item {}
                    onAccepted: {
                        var p = parseInt(text)
                        if (!isNaN(p) && p >= 1 && p <= quranBackend.totalPages()) {
                            currentPage = p
                            loadPage()
                        }
                        text = ""
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 44
                radius: 10
                color: "#0f6e56"
                Text { anchors.centerIn: parent; text: "Next page \u2192"; color: "#fff"; font.pixelSize: 13 }
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        if (currentPage < quranBackend.totalPages()) { currentPage += 1; loadPage() }
                    }
                }
            }
        }

        // ---- Mini audio bar ----
        // Persistent once a playback session has started this view instance;
        // stays visible even when paused/stopped so the user can resume,
        // switch reciter, or change loop mode without re-finding their verse.
        // Laid out as a regular flow item (not an absolute-positioned
        // overlay) so it never covers the mushaf prev/next-page row -
        // it just pushes content above it, like the rest of the layout.
        Rectangle {
            id: audioBar
            visible: audioSessionStarted
            Layout.fillWidth: true
            Layout.preferredHeight: 60
            radius: 16
            color: "#0f2a24"
            border.color: "#2f4b43"
            border.width: 1
            clip: true

            RowLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 10

                Rectangle {
                    width: 44; height: 44; radius: 22
                    color: "#0f6e56"
                    Text {
                        anchors.centerIn: parent
                        text: audioBackend.playing ? "\u23F8" : "\u25B6"
                        color: "#fff"
                        font.pixelSize: 16
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: view.toggleVersePlayback(audioBackend.currentSurah, audioBackend.currentAyah)
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    Text {
                        text: "Surah " + audioBackend.currentSurah + ", Ayah " + audioBackend.currentAyah
                            + (audioBackend.usingPlaylist
                                ? "  \u00b7  " + (audioBackend.playlistPosition + 1) + "/" + audioBackend.playlistLength + " selected"
                                : "")
                        color: "#e8f5ee"
                        font.pixelSize: 13
                        font.weight: Font.Medium
                    }
                    Text {
                        text: (audioErrorText !== "" ? audioErrorText
                            : (view.reciterList.length > 0
                                ? (view.reciterList.filter(function(r) { return r.id === selectedReciterId })[0] || {}).name || selectedReciterId
                                : selectedReciterId))
                        color: audioErrorText !== "" ? "#e88a7f" : "#8fb3a4"
                        font.pixelSize: 11
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }

                Rectangle {
                    width: 44; height: 44; radius: 22
                    color: "#173832"
                    Text {
                        anchors.centerIn: parent
                        text: audioBackend.loopMode === 1 ? "\uD83D\uDD01\u00B9" : (audioBackend.loopMode === 2 ? "\uD83D\uDD01" : "\u21BB")
                        color: audioBackend.loopMode !== 0 ? "#7fd6b4" : "#8fb3a4"
                        font.pixelSize: 14
                    }
                    MouseArea { anchors.fill: parent; onClicked: view.cycleLoopMode() }
                }

                Rectangle {
                    width: 44; height: 44; radius: 22
                    color: "#173832"
                    Text { anchors.centerIn: parent; text: "\uD83C\uDFA4"; color: "#8fb3a4"; font.pixelSize: 13 }
                    MouseArea { anchors.fill: parent; onClicked: showReciterPicker = true }
                }

                Rectangle {
                    width: 44; height: 44; radius: 22
                    color: "#173832"
                    Text { anchors.centerIn: parent; text: "\u2715"; color: "#8fb3a4"; font.pixelSize: 13 }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            audioBackend.stop()
                            audioSessionStarted = false
                        }
                    }
                }
            }
        }
    }

    // ---- Overlays ----
    Loader {
        active: showSurahPicker
        anchors.fill: parent
        sourceComponent: SurahPicker {
            onPicked: { view.goToSurah(surah, ayah); showSurahPicker = false }
            onClosed: showSurahPicker = false
            onPlaySelected: {
                pendingSelection = items
                reciterPickerForSelection = true
                showSurahPicker = false
                showReciterPicker = true
            }
        }
    }

    Loader {
        active: showJuzPicker
        anchors.fill: parent
        sourceComponent: JuzPicker {
            onPicked: { view.goToJuz(juz); showJuzPicker = false }
            onClosed: showJuzPicker = false
            onPlaySelected: {
                pendingSelection = items
                reciterPickerForSelection = true
                showJuzPicker = false
                showReciterPicker = true
            }
        }
    }

    Loader {
        active: showReciterPicker
        anchors.fill: parent
        sourceComponent: ReciterPicker {
            currentReciterId: selectedReciterId
            onPicked: {
                if (reciterPickerForSelection) {
                    view.startSelectionPlayback(reciterId)
                    reciterPickerForSelection = false
                    showReciterPicker = false
                    return
                }
                selectedReciterId = reciterId
                quranBackend.setPreference("reciterId", reciterId)
                // Hot-swap without losing playback position/state if a
                // session is already active (setReciter restarts the
                // current verse under the new reciter only if something
                // was already loaded/playing).
                if (audioSessionStarted) audioBackend.setReciter(reciterId)
                showReciterPicker = false
            }
            onClosed: { reciterPickerForSelection = false; showReciterPicker = false }
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
                    Text { text: "Layout"; color: "#8fb3a4"; font.pixelSize: 12 }
                    RowLayout {
                        spacing: 8
                        Layout.fillWidth: true
                        Rectangle {
                            Layout.fillWidth: true; height: 38; radius: 10
                            color: layoutMode === "reading" ? "#0f6e56" : "#10241f"
                            Text { anchors.centerIn: parent; text: "Reading"; color: "#fff"; font.pixelSize: 12 }
                            MouseArea { anchors.fill: parent; onClicked: layoutMode = "reading" }
                        }
                        Rectangle {
                            Layout.fillWidth: true; height: 38; radius: 10
                            color: layoutMode === "mushaf" ? "#0f6e56" : "#10241f"
                            Text { anchors.centerIn: parent; text: "Mushaf (Hafizi)"; color: "#fff"; font.pixelSize: 12 }
                            MouseArea { anchors.fill: parent; onClicked: { layoutMode = "mushaf"; loadPage() } }
                        }
                    }
                }

                ColumnLayout {
                    spacing: 8
                    visible: layoutMode === "reading"
                    Text { text: "Translations shown"; color: "#8fb3a4"; font.pixelSize: 12 }

                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: "Sahih International (English)"; color: "#dff2ea"; font.pixelSize: 13; Layout.fillWidth: true }
                        Switch { checked: showEnglish; onToggled: showEnglish = checked }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: "Kanzul Iman (Urdu)"; color: "#dff2ea"; font.pixelSize: 13; Layout.fillWidth: true }
                        Switch { checked: showUrdu; onToggled: showUrdu = checked }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: "Tafsir Jalalayn"; color: "#dff2ea"; font.pixelSize: 13; Layout.fillWidth: true }
                        Switch { checked: showTafsir; onToggled: showTafsir = checked }
                    }
                }

                ColumnLayout {
                    spacing: 8
                    Text { text: "Arabic text size"; color: "#8fb3a4"; font.pixelSize: 12 }
                    RowLayout {
                        spacing: 8
                        Layout.fillWidth: true
                        Repeater {
                            model: [ {k:"small",l:"A"}, {k:"medium",l:"A"}, {k:"large",l:"A"} ]
                            delegate: Rectangle {
                                Layout.fillWidth: true; height: 38; radius: 10
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
                    MouseArea { anchors.fill: parent; onClicked: { showSettings = false; persistPrefs() } }
                }
            }
        }
    }
}
