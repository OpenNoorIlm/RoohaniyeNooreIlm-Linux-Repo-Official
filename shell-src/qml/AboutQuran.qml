import QtQuick 2.15
import QtQuick.Layouts 1.15

// "About Quran" panel reached from QuranMenu.qml's info tile.
// Pure display of quranBackend.quranStats() - no navigation state of its
// own, no editing. Structure counts (surahs/ayahs/juz/etc.) are fixed
// constants on the backend; sajda counts are queried live from the db.
Rectangle {
    id: about
    anchors.fill: parent
    color: "#10241f"

    property var stats: quranBackend.quranStats()

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
            Text { text: "About the Quran"; color: "#e8f5ee"; font.pixelSize: 22; font.weight: Font.Medium; Layout.leftMargin: 12 }
        }

        Text {
            text: "The Holy Quran is divided into structural units used for study, memorisation, and recitation scheduling. Structure below reflects the standard Uthmani mushaf layout."
            color: "#8fb3a4"
            font.pixelSize: 13
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: 14
            rowSpacing: 14

            Repeater {
                model: [
                    { label: "Surahs", value: stats.surahs, sub: "Chapters" },
                    { label: "Ayahs", value: stats.ayahs, sub: "Verses" },
                    { label: "Juz", value: stats.juz, sub: "30 parts" },
                    { label: "Pages", value: stats.pages, sub: "Standard mushaf" },
                    { label: "Manzils", value: stats.manzils, sub: "7 portions, one per week" },
                    { label: "Rukus", value: stats.rukus, sub: "Thematic passages" },
                    { label: "Hizb quarters", value: stats.hizbQuarters, sub: "Quarter-juz markers" },
                    { label: "Sajdas", value: stats.sajdas !== undefined ? stats.sajdas : "\u2013", sub: (stats.sajdasObligatory !== undefined ? stats.sajdasObligatory + " obligatory" : "Prostration verses") }
                ]

                delegate: Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 92
                    radius: 16
                    color: "#173832"

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 2
                        Text { text: modelData.value; color: "#7fd6b4"; font.pixelSize: 26; font.weight: Font.Medium }
                        Text { text: modelData.label; color: "#e8f5ee"; font.pixelSize: 13 }
                        Item { Layout.fillHeight: true }
                        Text { text: modelData.sub; color: "#8fb3a4"; font.pixelSize: 10; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                    }
                }
            }
        }

        Item { Layout.fillHeight: true }
    }
}
