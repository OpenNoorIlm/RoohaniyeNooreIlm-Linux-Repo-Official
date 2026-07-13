import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15

Rectangle {
    id: appCenterRoot
    anchors.fill: parent
    color: "#10241f"

    // "Explore" | "Featured" | a category name | "Manage" | "About"
    property string activeSection: "Explore"
    property string searchText: ""

    readonly property var categories: ["Productivity", "Development"]

    Component.onCompleted: appCenter.refreshManifest()

    function appsForSection(section) {
        var all = appCenter.apps
        var filtered = []
        for (var i = 0; i < all.length; i++) {
            var app = all[i]
            var matchesSection =
                section === "Explore" ? true :
                section === "Featured" ? (i < 3) : // first 3 = "featured" until the manifest has a real flag
                app.category === section
            var matchesSearch = searchText === "" ||
                app.name.toLowerCase().indexOf(searchText.toLowerCase()) !== -1
            if (matchesSection && matchesSearch) filtered.push(app)
        }
        return filtered
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ---- Sidebar ----
        Rectangle {
            Layout.preferredWidth: 200
            Layout.fillHeight: true
            color: "#0c1d19"

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 0
                spacing: 0

                RowLayout {
                    Layout.fillWidth: true
                    Layout.margins: 16
                    Text {
                        text: "\u2190"
                        color: "#7fd6b4"
                        font.pixelSize: 18
                        MouseArea { anchors.fill: parent; onClicked: root.currentView = "home" }
                    }
                    Text { text: "App Center"; color: "#e8f5ee"; font.pixelSize: 15; font.weight: Font.Medium; Layout.leftMargin: 10 }
                }

                Repeater {
                    model: [
                        {label: "Explore", icon: "\u25C9"},
                        {label: "Featured", icon: "\u2605"}
                    ]
                    delegate: SidebarItem {
                        label: modelData.label
                        icon: modelData.icon
                        active: activeSection === modelData.label
                        onClicked: activeSection = modelData.label
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: "#1c3830"; Layout.topMargin: 8; Layout.bottomMargin: 8 }

                Repeater {
                    model: categories
                    delegate: SidebarItem {
                        label: modelData
                        icon: "\u25A1"
                        active: activeSection === modelData
                        onClicked: activeSection = modelData
                    }
                }

                Item { Layout.fillHeight: true }

                Rectangle { Layout.fillWidth: true; height: 1; color: "#1c3830" }

                SidebarItem {
                    label: "Manage"
                    icon: "\u2699"
                    active: activeSection === "Manage"
                    badge: appCenter.availableUpdates().length
                    onClicked: activeSection = "Manage"
                }
                SidebarItem {
                    label: "About"
                    icon: "?"
                    active: activeSection === "About"
                    onClicked: activeSection = "About"
                    isLast: true
                }
            }
        }

        // ---- Main content ----
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // Top bar: search + status
            RowLayout {
                Layout.fillWidth: true
                Layout.margins: 20
                spacing: 14

                Rectangle {
                    Layout.fillWidth: true
                    Layout.maximumWidth: 420
                    height: 38
                    radius: 10
                    color: "#173832"
                    visible: activeSection !== "About"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 8
                        Text { text: "\u26B2"; color: "#7fb3a0"; font.pixelSize: 13 }
                        TextField {
                            Layout.fillWidth: true
                            placeholderText: "Search for apps"
                            placeholderTextColor: "#5f8a7b"
                            color: "#e8f5ee"
                            background: Item {}
                            text: searchText
                            onTextChanged: searchText = text
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                BusyIndicator { running: appCenter.busy; visible: appCenter.busy; width: 20; height: 20 }
                Text { text: appCenter.statusMessage; color: "#8fb3a4"; font.pixelSize: 11 }
            }

            // ---- Explore / Featured / category pages ----
            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: activeSection !== "Manage" && activeSection !== "About"
                clip: true

                ColumnLayout {
                    width: appCenterRoot.width - 200 - 40
                    spacing: 20

                    // Featured banner, only on the Explore landing page
                    Rectangle {
                        visible: activeSection === "Explore" && searchText === ""
                        Layout.fillWidth: true
                        Layout.leftMargin: 20
                        Layout.rightMargin: 20
                        Layout.topMargin: 4
                        height: 130
                        radius: 18
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: "#1d3d6b" }
                            GradientStop { position: 1.0; color: "#0f6e56" }
                        }

                        ColumnLayout {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: 24
                            spacing: 10
                            Text { text: "Curated for RoohaniyeNoorIlmLinux"; color: "#ffffff"; font.pixelSize: 20; font.weight: Font.Medium }
                            Text { text: "Every app here is free, open source, and verified before it reaches you."; color: "#dbeee6"; font.pixelSize: 12 }
                        }
                    }

                    Text {
                        Layout.leftMargin: 20
                        Layout.topMargin: 8
                        text: activeSection
                        color: "#e8f5ee"
                        font.pixelSize: 17
                        font.weight: Font.Medium
                    }

                    Text {
                        visible: appsForSection(activeSection).length === 0 && !appCenter.busy
                        Layout.leftMargin: 20
                        text: searchText !== "" ? "No apps match \u201c" + searchText + "\u201d." : "Nothing here yet."
                        color: "#7fb3a0"
                        font.pixelSize: 13
                    }

                    GridView {
                        Layout.leftMargin: 16
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.ceil(appsForSection(activeSection).length / Math.max(1, Math.floor(width / 240))) * 190
                        cellWidth: 240
                        cellHeight: 185
                        model: appsForSection(activeSection)
                        interactive: false
                        clip: true

                        delegate: AppCard {
                            app: modelData
                            installed: appCenter.isInstalled(modelData.id)
                            onInstallRequested: appCenter.installApp(modelData.id)
                        }
                    }

                    Item { Layout.preferredHeight: 20 }
                }
            }

            // ---- Manage page ----
            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: activeSection === "Manage"
                clip: true

                ColumnLayout {
                    width: appCenterRoot.width - 200 - 40
                    Layout.leftMargin: 20
                    Layout.rightMargin: 20
                    spacing: 20

                    Text { text: "Manage"; color: "#e8f5ee"; font.pixelSize: 22; font.weight: Font.Medium; Layout.topMargin: 4 }

                    // Updates available
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        visible: appCenter.availableUpdates().length > 0

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "Updates available (" + appCenter.availableUpdates().length + ")"
                                color: "#e8f5ee"
                                font.pixelSize: 15
                                font.weight: Font.Medium
                                Layout.fillWidth: true
                            }
                            Rectangle {
                                width: 130; height: 34; radius: 8
                                color: "#0f6e56"
                                Text { anchors.centerIn: parent; text: "Update all"; color: "#fff"; font.pixelSize: 12 }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        var updates = appCenter.availableUpdates()
                                        for (var i = 0; i < updates.length; i++) appCenter.installApp(updates[i].id)
                                    }
                                }
                            }
                        }

                        Repeater {
                            model: appCenter.availableUpdates()
                            delegate: Rectangle {
                                Layout.fillWidth: true
                                height: 56
                                radius: 12
                                color: "#173832"
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 12
                                    Rectangle {
                                        width: 32; height: 32; radius: 8
                                        color: "#0f6e56"
                                        Text { anchors.centerIn: parent; text: (modelData.name || "?").charAt(0); color: "#fff"; font.pixelSize: 14 }
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1
                                        Text { text: modelData.name; color: "#e8f5ee"; font.pixelSize: 13 }
                                        Text { text: modelData.installedVersion + " \u2192 " + modelData.availableVersion; color: "#8fb3a4"; font.pixelSize: 11 }
                                    }
                                    Rectangle {
                                        width: 80; height: 30; radius: 8
                                        color: "#0f6e56"
                                        Text { anchors.centerIn: parent; text: "Update"; color: "#fff"; font.pixelSize: 12 }
                                        MouseArea { anchors.fill: parent; onClicked: appCenter.installApp(modelData.id) }
                                    }
                                }
                            }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: "#1c3830"; visible: appCenter.availableUpdates().length > 0 }

                    // Installed apps
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Text { text: "Installed apps"; color: "#e8f5ee"; font.pixelSize: 15; font.weight: Font.Medium }

                        Text {
                            visible: appCenter.installedApps().length === 0
                            text: "Nothing installed through the App Center yet."
                            color: "#7fb3a0"
                            font.pixelSize: 13
                        }

                        Repeater {
                            model: appCenter.installedApps()
                            delegate: Rectangle {
                                Layout.fillWidth: true
                                height: 56
                                radius: 12
                                color: "#173832"
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 12
                                    Rectangle {
                                        width: 32; height: 32; radius: 8
                                        color: "#0f6e56"
                                        Text { anchors.centerIn: parent; text: (modelData.name || "?").charAt(0); color: "#fff"; font.pixelSize: 14 }
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1
                                        Text { text: modelData.name; color: "#e8f5ee"; font.pixelSize: 13 }
                                        Text { text: "v" + modelData.version + (modelData.license ? "  \u00b7  " + modelData.license : ""); color: "#8fb3a4"; font.pixelSize: 11 }
                                    }
                                    Rectangle {
                                        width: 90; height: 30; radius: 8
                                        color: "#3a1f1f"
                                        Text { anchors.centerIn: parent; text: "Uninstall"; color: "#e8a89c"; font.pixelSize: 12 }
                                        MouseArea { anchors.fill: parent; onClicked: appCenter.uninstallApp(modelData.id) }
                                    }
                                }
                            }
                        }
                    }

                    Item { Layout.preferredHeight: 20 }
                }
            }

            // ---- About page ----
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.margins: 20
                visible: activeSection === "About"
                spacing: 10

                Text { text: "About App Center"; color: "#e8f5ee"; font.pixelSize: 20; font.weight: Font.Medium }
                Text {
                    text: "Every app listed here is free and open source, and installs come straight "
                        + "from that project's own official release - never a repackaged or third-party build."
                    color: "#9fc9b8"
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                    Layout.preferredWidth: 480
                }
                Text {
                    text: "Downloads are SHA-256 verified against the published manifest before anything is installed."
                    color: "#9fc9b8"
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                    Layout.preferredWidth: 480
                    Layout.topMargin: 4
                }
                Item { Layout.fillHeight: true }
            }
        }
    }

    component SidebarItem: Rectangle {
        property string label: ""
        property string icon: ""
        property bool active: false
        property int badge: 0
        property bool isLast: false
        signal clicked()

        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        Layout.bottomMargin: isLast ? 12 : 0
        height: 40
        radius: 10
        color: active ? "#173832" : "transparent"

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 10
            Text { text: icon; color: active ? "#7fd6b4" : "#8fb3a4"; font.pixelSize: 13 }
            Text { text: label; color: active ? "#e8f5ee" : "#a8c9bd"; font.pixelSize: 13; Layout.fillWidth: true }
            Rectangle {
                visible: badge > 0
                width: 18; height: 18; radius: 9
                color: "#0f6e56"
                Text { anchors.centerIn: parent; text: badge; color: "#fff"; font.pixelSize: 9 }
            }
        }

        MouseArea { anchors.fill: parent; onClicked: parent.clicked() }
    }

    component AppCard: Rectangle {
        id: card
        property var app
        property bool installed: false
        signal installRequested()

        width: 220; height: 170
        radius: 16
        color: "#173832"

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Rectangle {
                    width: 40; height: 40; radius: 10
                    color: "#0f6e56"
                    Text { anchors.centerIn: parent; text: (card.app.name || "?").charAt(0); color: "#fff"; font.pixelSize: 16 }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    Text { text: card.app.name; color: "#dff2ea"; font.pixelSize: 14; font.weight: Font.Medium; elide: Text.ElideRight; Layout.fillWidth: true }
                    RowLayout {
                        spacing: 4
                        Text { text: card.app.publisher !== "" ? card.app.publisher : "Community"; color: "#7fb3a0"; font.pixelSize: 10 }
                        Text { text: "\u2713"; color: "#0f6e56"; font.pixelSize: 10 }
                    }
                }
            }

            Text {
                text: card.app.description || ""
                color: "#9fc9b8"
                font.pixelSize: 11
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                Layout.fillHeight: true
                maximumLineCount: 3
                elide: Text.ElideRight
            }

            Rectangle {
                Layout.fillWidth: true
                height: 30
                radius: 8
                color: card.installed ? "#20463c" : (installMouse.pressed ? "#0d5947" : "#0f6e56")
                Text {
                    anchors.centerIn: parent
                    text: card.installed ? "Installed" : "Install"
                    color: card.installed ? "#7fd6b4" : "#ffffff"
                    font.pixelSize: 12
                }
                MouseArea {
                    id: installMouse
                    anchors.fill: parent
                    enabled: !card.installed
                    onClicked: card.installRequested()
                }
            }
        }
    }
}
