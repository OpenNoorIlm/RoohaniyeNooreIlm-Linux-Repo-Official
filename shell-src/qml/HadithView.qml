import QtQuick 2.15
import QtQuick.Layouts 1.15

Rectangle {
    anchors.fill: parent
    color: "#10241f"

    property var hadith: quranBackend.randomHadith()

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
                MouseArea { anchors.fill: parent; onClicked: root.currentView = "home" }
            }
            Text { text: "Hadith"; color: "#e8f5ee"; font.pixelSize: 18; font.weight: Font.Medium; Layout.leftMargin: 12 }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 16
            color: "#3c3489"

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 24
                spacing: 12

                Text {
                    text: hadith.english || "No hadith available yet."
                    color: "#ffffff"
                    font.pixelSize: 16
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
                Text {
                    text: (hadith.book || "") + (hadith.hadith_num ? (" \u2022 #" + hadith.hadith_num) : "")
                    color: "#beb9ec"
                    font.pixelSize: 12
                }
                Item { Layout.fillHeight: true }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 44
            radius: 10
            color: "#0f6e56"
            Text { anchors.centerIn: parent; text: "Another hadith"; color: "#fff"; font.pixelSize: 13 }
            MouseArea {
                anchors.fill: parent
                onClicked: hadith = quranBackend.randomHadith()
            }
        }
    }
}
