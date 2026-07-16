import QtQuick 2.15
import QtQuick.Layouts 1.15

// Landing screen for the "Quran Mushaf" feature: lets the user pick one
// of the scanned mushaf editions in mushafs.db, then opens
// MushafReader.qml on that edition (resuming its own last-read page if
// one was saved, otherwise starting at page 1 / that edition's minPage).
Rectangle {
    id: gallery
    anchors.fill: parent
    color: "#10241f"

    property var mushafs: mushafBackend.mushafList()
    property var lastProgress: mushafBackend.lastProgress()

    function displayNameFor(mushafName) {
        for (var i = 0; i < mushafs.length; i++) {
            if (mushafs[i].mushafName === mushafName) return mushafs[i].displayName
        }
        return mushafName
    }

    function openMushaf(mushafName, page) {
        root.navMushafName = mushafName
        root.navMushafPage = page !== undefined ? page : -1
        root.navigateTo("mushafreader")
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
            Text { text: "Quran Mushaf"; color: "#e8f5ee"; font.pixelSize: 22; font.weight: Font.Medium; Layout.leftMargin: 12 }
        }

        Text {
            text: "Choose a mushaf edition to read page by page, exactly as printed."
            color: "#8fb3a4"
            font.pixelSize: 12
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        // ---- Continue reading ----
        Rectangle {
            visible: lastProgress.mushafName !== undefined
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
                        text: (lastProgress.mushafName !== undefined
                               ? gallery.displayNameFor(lastProgress.mushafName) : "")
                              + "  \u00b7  Page " + lastProgress.pageNumber
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
                onClicked: gallery.openMushaf(lastProgress.mushafName, lastProgress.pageNumber)
            }
        }

        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 12
            model: gallery.mushafs

            delegate: Rectangle {
                width: ListView.view.width
                height: 84
                radius: 16
                color: "#173832"
                scale: tileMouse.pressed ? 0.98 : 1.0
                Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 14

                    Rectangle {
                        width: 48; height: 48; radius: 12
                        color: "#0f6e56"
                        Text { anchors.centerIn: parent; text: "\u25A6"; color: "#fff"; font.pixelSize: 20 }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Text {
                            text: modelData.displayName
                            color: "#e8f5ee"
                            font.pixelSize: 15
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        Text {
                            text: modelData.pageCount + " pages"
                            color: "#8fb3a4"
                            font.pixelSize: 11
                        }
                    }

                    Text { text: "\u2192"; color: "#7fd6b4"; font.pixelSize: 16 }
                }

                MouseArea {
                    id: tileMouse
                    anchors.fill: parent
                    onClicked: gallery.openMushaf(modelData.mushafName, modelData.minPage)
                }
            }
        }
    }
}
