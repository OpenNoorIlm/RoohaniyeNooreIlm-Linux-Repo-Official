import QtQuick 2.15
import QtQuick.Layouts 1.15

// "Database Connector" app: browse a mounted USB/SD card, pick a .db (or
// a folder/.json to be converted into one), see which built-in apps its
// schema matches, tap one to connect it. Backed by dbConnectorBackend
// (browsing/import/schema-match) and storageBackend (device detection -
// this screen is only reachable once storageBackend.storagePresent is
// true, see HomeScreen.qml's tile).
//
// No local `id: root` here (same convention as QuranMenu.qml etc) -
// `root` below refers to Main.qml's Window, reached via QML's normal
// scope walk through the Loader, so `root.currentView = ...` navigates
// like every other screen.
//
// Three stages:
//   "browse"  - file/folder list at currentPath
//   "matches" - result of importPath(): matched app cards to tap
//   "done"    - result of connectToApp(): success/failure message
Rectangle {
    id: connectorRoot
    anchors.fill: parent
    color: "#10241f"

    property string stage: "browse"
    property string currentPath: storageBackend.devices.length > 0 ? storageBackend.devices[0].path : "/media"
    property var pathStack: []
    property var importResult: ({ ok: false })
    property var connectResult: ({ ok: false, requiresRestart: false })

    function goInto(item) {
        pathStack.push(currentPath)
        currentPath = item.path
    }
    function goBack() {
        if (pathStack.length > 0) {
            currentPath = pathStack.pop()
        } else {
            root.goBack()
        }
    }
    function doImport(item) {
        importResult = dbConnectorBackend.importPath(item.path)
        stage = "matches"
    }
    function doConnect(appId) {
        connectResult = dbConnectorBackend.connectToApp(importResult.importedPath, appId)
        stage = "done"
    }

    // Re-list whenever we land back on "browse" for the current path.
    property var listing: stage === "browse" ? dbConnectorBackend.listDirectory(currentPath) : []

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 28
        spacing: 16

        // ---- Header ----
        RowLayout {
            Layout.fillWidth: true
            Text {
                text: "\u2190"
                color: "#7fd6b4"
                font.pixelSize: 20
                MouseArea {
                    anchors.fill: parent
                    onClicked: { root.sounds.buttonClick();
                        if (connectorRoot.stage === "browse") connectorRoot.goBack()
                        else if (connectorRoot.stage === "matches") connectorRoot.stage = "browse"
                        else root.goBack()
                    }
                }
            }
            ColumnLayout {
                spacing: 2
                Layout.leftMargin: 12
                Text { text: "Database Connector"; color: "#e8f5ee"; font.pixelSize: 20; font.weight: Font.Medium }
                Text {
                    text: connectorRoot.stage === "browse" ? connectorRoot.currentPath : (connectorRoot.stage === "matches" ? "Choose an app to connect" : "")
                    color: "#8fb3a4"
                    font.pixelSize: 12
                    elide: Text.ElideMiddle
                    Layout.maximumWidth: 500
                }
            }
        }

        // ---- Stage: browse ----
        ListView {
            visible: connectorRoot.stage === "browse"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 8
            model: connectorRoot.listing

            delegate: Rectangle {
                width: ListView.view.width
                height: 64
                radius: 14
                color: "#173832"
                scale: rowMouse.pressed ? 0.98 : 1.0
                Behavior on scale { NumberAnimation { duration: 100 } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 14

                    Text {
                        text: modelData.isDir ? "\u{1F4C1}" : (modelData.isDb ? "\u{1F5C4}" : (modelData.isJson ? "{ }" : "\u2022"))
                        color: "#7fd6b4"
                        font.pixelSize: 18
                    }
                    ColumnLayout {
                        spacing: 1
                        Layout.fillWidth: true
                        Text { text: modelData.name; color: "#dff2ea"; font.pixelSize: 14; elide: Text.ElideRight; Layout.fillWidth: true }
                        Text {
                            text: modelData.isDir ? "Folder" : modelData.sizeLabel
                            color: "#8fb3a4"
                            font.pixelSize: 11
                        }
                    }
                    Rectangle {
                        visible: modelData.isDir || modelData.isDb || modelData.isJson
                        radius: 10
                        color: "#0f6e56"
                        Layout.preferredWidth: 76
                        Layout.preferredHeight: 32
                        Text { anchors.centerIn: parent; text: "Import"; color: "#ffffff"; font.pixelSize: 12; font.weight: Font.Medium }
                        MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: { root.sounds.buttonClick(); connectorRoot.doImport(modelData) } }
                    }
                }

                MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    z: -1 // let the Import button above take priority on click
                    onClicked: { root.sounds.buttonClick(); if (modelData.isDir) connectorRoot.goInto(modelData) }
                }
            }

            Text {
                anchors.centerIn: parent
                visible: connectorRoot.listing.length === 0
                text: "Nothing here"
                color: "#5f8579"
                font.pixelSize: 14
            }
        }

        // ---- Stage: matches ----
        ColumnLayout {
            visible: connectorRoot.stage === "matches"
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 14

            Text {
                visible: !connectorRoot.importResult.ok
                text: connectorRoot.importResult.error ? connectorRoot.importResult.error : ""
                color: "#f2a3a3"
                font.pixelSize: 14
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            Text {
                visible: connectorRoot.importResult.ok && connectorRoot.importResult.matchedApps && connectorRoot.importResult.matchedApps.length === 0
                text: "Imported, but this database's structure doesn't match any app on this device."
                color: "#c9b98a"
                font.pixelSize: 14
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            Repeater {
                model: connectorRoot.importResult.ok ? connectorRoot.importResult.matchedApps : []
                delegate: Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 76
                    radius: 16
                    color: "#173832"
                    scale: appMouse.pressed ? 0.98 : 1.0
                    Behavior on scale { NumberAnimation { duration: 100 } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        ColumnLayout {
                            spacing: 2
                            Layout.fillWidth: true
                            Text { text: modelData.name; color: "#dff2ea"; font.pixelSize: 15; font.weight: Font.Medium }
                            Text { text: "table: " + modelData.tableMatched; color: "#8fb3a4"; font.pixelSize: 11 }
                        }
                        Text { text: "\u2192"; color: "#7fd6b4"; font.pixelSize: 18 }
                    }

                    MouseArea {
                        id: appMouse
                        anchors.fill: parent
                        onClicked: { root.sounds.buttonClick(); connectorRoot.doConnect(modelData.id) }
                    }
                }
            }

            Item { Layout.fillHeight: true }
        }

        // ---- Stage: done ----
        ColumnLayout {
            visible: connectorRoot.stage === "done"
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 12

            Text {
                text: connectorRoot.connectResult.ok ? "\u2713 Connected" : "Couldn't connect"
                color: connectorRoot.connectResult.ok ? "#7fd6b4" : "#f2a3a3"
                font.pixelSize: 20
                font.weight: Font.Medium
            }
            Text {
                visible: !connectorRoot.connectResult.ok
                text: connectorRoot.connectResult.error ? connectorRoot.connectResult.error : ""
                color: "#f2a3a3"
                font.pixelSize: 13
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
            Text {
                visible: connectorRoot.connectResult.ok && connectorRoot.connectResult.requiresRestart
                text: "This app needs the shell restarted to start using it."
                color: "#c9b98a"
                font.pixelSize: 13
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
            Text {
                visible: connectorRoot.connectResult.ok && !connectorRoot.connectResult.requiresRestart
                text: "It's active now - no restart needed."
                color: "#8fb3a4"
                font.pixelSize: 13
            }

            Rectangle {
                Layout.preferredWidth: 140
                Layout.preferredHeight: 44
                Layout.topMargin: 8
                radius: 12
                color: "#0f6e56"
                Text { anchors.centerIn: parent; text: "Done"; color: "#ffffff"; font.pixelSize: 14; font.weight: Font.Medium }
                MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: { root.sounds.buttonClick(); root.currentView = "home" } }
            }

            Item { Layout.fillHeight: true }
        }
    }
}
