import QtQuick 2.15
import QtQuick.Layouts 1.15

// "Prayer times" app: today's six prayer times + countdown to the next
// one, for the saved location. Backed by prayerBackend - see
// prayerbackend.h for the calculation approach and its limitations.
Rectangle {
    id: prayerRoot
    anchors.fill: parent
    color: "#10241f"

    property var loc: prayerBackend.location()
    property var times: loc.hasLocation ? prayerBackend.prayerTimesToday() : []
    property var next: loc.hasLocation ? prayerBackend.nextPrayer() : ({})
    property var calc: prayerBackend.calculationSettings()
    property bool showSettings: false

    readonly property var presets: [
        { name: "Muslim World League", fajr: 18.0, isha: 17.0 },
        { name: "ISNA (North America)", fajr: 15.0, isha: 15.0 },
        { name: "Egyptian General Authority", fajr: 19.5, isha: 17.5 },
        { name: "University of Islamic Sciences, Karachi", fajr: 18.0, isha: 18.0 }
    ]

    // NOTE: prayerBackend's Q_INVOKABLE getters (location()/
    // calculationSettings()/etc.) are plain function calls, not
    // NOTIFY-backed properties, so QML won't auto-refresh bindings that
    // read them directly. Every place in this file that changes
    // location or calc settings must call refresh() afterward so these
    // cached copies (and everything bound to them) update.
    function refresh() {
        prayerRoot.loc = prayerBackend.location()
        prayerRoot.times = prayerRoot.loc.hasLocation ? prayerBackend.prayerTimesToday() : []
        prayerRoot.next = prayerRoot.loc.hasLocation ? prayerBackend.nextPrayer() : ({})
        prayerRoot.calc = prayerBackend.calculationSettings()
    }

    // Recompute the countdown once a minute so "next prayer" and the
    // minutes-remaining figure stay live without needing a manual
    // refresh or a re-visit to this screen.
    Timer {
        interval: 60000
        running: true
        repeat: true
        onTriggered: prayerRoot.refresh()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 28
        spacing: 18

        RowLayout {
            Layout.fillWidth: true
            Text {
                text: "\u2190"
                color: "#7fd6b4"
                font.pixelSize: 20
                MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: { root.sounds.buttonClick(); root.goBack() } }
            }
            Text {
                text: "Prayer times"
                color: "#e8f5ee"
                font.pixelSize: 20
                font.weight: Font.Medium
                Layout.leftMargin: 12
            }
            Item { Layout.fillWidth: true }
            Text {
                visible: prayerRoot.loc.hasLocation
                text: "\u2699"
                color: "#7fd6b4"
                font.pixelSize: 18
                MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: { root.sounds.buttonClick(); prayerRoot.showSettings = !prayerRoot.showSettings } }
            }
        }

        // ---- No location set yet ----
        ColumnLayout {
            visible: !prayerRoot.loc.hasLocation
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 16

            Item { Layout.fillHeight: true; Layout.preferredHeight: 1 }
            Text {
                text: "Set your location to see today's prayer times."
                color: "#8fb3a4"
                font.pixelSize: 14
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
            }
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 220
                Layout.preferredHeight: 48
                radius: 12
                color: "#0f6e56"
                Text { anchors.centerIn: parent; text: "Choose location"; color: "#fff"; font.pixelSize: 14; font.weight: Font.Medium }
                MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: { root.sounds.buttonClick(); locationLoader.active = true } }
            }
            Item { Layout.fillHeight: true; Layout.preferredHeight: 2 }
        }

        // ---- Location set: show times ----
        ColumnLayout {
            visible: prayerRoot.loc.hasLocation && !prayerRoot.showSettings
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 14

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: prayerRoot.loc.label
                    color: "#8fb3a4"
                    font.pixelSize: 13
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
                Text {
                    text: "Change"
                    color: "#7fd6b4"
                    font.pixelSize: 12
                    MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: { root.sounds.buttonClick(); locationLoader.active = true } }
                }
            }

            // ---- Next prayer card ----
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 100
                radius: 18
                color: "#0f6e56"
                visible: prayerRoot.next.label !== undefined

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 18
                    spacing: 2
                    Text {
                        text: (prayerRoot.next.isTomorrow ? "Tomorrow \u2022 " : "Next \u2022 ") + (prayerRoot.next.label || "")
                        color: "#bfe9d8"
                        font.pixelSize: 13
                    }
                    Text {
                        text: prayerRoot.next.hhmm || ""
                        color: "#ffffff"
                        font.pixelSize: 30
                        font.weight: Font.Medium
                    }
                    Text {
                        text: prayerRoot.next.minutesUntil !== undefined
                              ? "in " + Math.floor(prayerRoot.next.minutesUntil / 60) + "h "
                                + (prayerRoot.next.minutesUntil % 60) + "m"
                              : ""
                        color: "#bfe9d8"
                        font.pixelSize: 12
                    }
                }
            }

            // ---- Today's six prayer times ----
            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 8
                model: prayerRoot.times

                delegate: Rectangle {
                    width: ListView.view.width
                    height: 52
                    radius: 12
                    color: (prayerRoot.next.label === modelData.label) ? "#173832" : "transparent"
                    border.color: "#1e453c"
                    border.width: (prayerRoot.next.label === modelData.label) ? 0 : 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        Text {
                            text: modelData.label
                            color: (prayerRoot.next.label === modelData.label) ? "#7fd6b4" : "#dff2ea"
                            font.pixelSize: 14
                            font.weight: (prayerRoot.next.label === modelData.label) ? Font.Medium : Font.Normal
                            Layout.fillWidth: true
                        }
                        Text {
                            text: modelData.hhmm
                            color: (prayerRoot.next.label === modelData.label) ? "#7fd6b4" : "#dff2ea"
                            font.pixelSize: 14
                        }
                    }
                }
            }
        }

        // ---- Calculation settings panel ----
        ColumnLayout {
            visible: prayerRoot.loc.hasLocation && prayerRoot.showSettings
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 14

            Text { text: "Calculation method"; color: "#8fb3a4"; font.pixelSize: 13; font.weight: Font.Medium }

            Repeater {
                model: prayerRoot.presets
                delegate: Rectangle {
                    Layout.fillWidth: true
                    height: 52
                    radius: 12
                    color: (prayerRoot.calc.fajrAngle === modelData.fajr && prayerRoot.calc.ishaAngle === modelData.isha)
                           ? "#0f6e56" : "#173832"

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        Text { text: modelData.name; color: "#dff2ea"; font.pixelSize: 13; Layout.fillWidth: true }
                        Text { text: modelData.fajr + "\u00b0/" + modelData.isha + "\u00b0"; color: "#8fb3a4"; font.pixelSize: 11 }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: { root.sounds.buttonClick();
                            prayerBackend.setCalculationSettings(modelData.fajr, modelData.isha, prayerRoot.calc.asrFactor)
                            prayerRoot.refresh()
                        }
                    }
                }
            }

            Text { text: "Asr method"; color: "#8fb3a4"; font.pixelSize: 13; font.weight: Font.Medium; Layout.topMargin: 10 }

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Rectangle {
                    Layout.fillWidth: true
                    height: 48
                    radius: 12
                    color: prayerRoot.calc.asrFactor === 1 ? "#0f6e56" : "#173832"
                    Text { anchors.centerIn: parent; text: "Standard\n(Shafi/Maliki/Hanbali)"; horizontalAlignment: Text.AlignHCenter; color: "#fff"; font.pixelSize: 12 }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: { root.sounds.buttonClick();
                            prayerBackend.setCalculationSettings(prayerRoot.calc.fajrAngle, prayerRoot.calc.ishaAngle, 1)
                            prayerRoot.refresh()
                        }
                    }
                }
                Rectangle {
                    Layout.fillWidth: true
                    height: 48
                    radius: 12
                    color: prayerRoot.calc.asrFactor === 2 ? "#0f6e56" : "#173832"
                    Text { anchors.centerIn: parent; text: "Hanafi"; color: "#fff"; font.pixelSize: 13 }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: { root.sounds.buttonClick();
                            prayerBackend.setCalculationSettings(prayerRoot.calc.fajrAngle, prayerRoot.calc.ishaAngle, 2)
                            prayerRoot.refresh()
                        }
                    }
                }
            }

            Item { Layout.fillHeight: true }

            Rectangle {
                Layout.fillWidth: true
                height: 48
                radius: 12
                color: "#173832"
                Text { anchors.centerIn: parent; text: "Done"; color: "#dff2ea"; font.pixelSize: 14 }
                MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: { root.sounds.buttonClick(); prayerRoot.showSettings = false; prayerRoot.refresh() } }
            }
        }
    }

    Loader {
        id: locationLoader
        anchors.fill: parent
        active: false
        source: "LocationPicker.qml"
        onLoaded: {
            item.saved.connect(function() { locationLoader.active = false; prayerRoot.refresh() })
            item.closed.connect(function() { locationLoader.active = false })
        }
    }
}
