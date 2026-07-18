import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15

Rectangle {
    anchors.fill: parent
    color: root.theme.hasBackground ? "transparent" : root.theme.bg
    property string selectedSsid: ""
    property string powerAction: ""

    Component.onCompleted: {
        wifiBackend.refreshWifiState()
        if (wifiBackend.wifiEnabled) wifiBackend.scan()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 32
        spacing: 20

        RowLayout {
            Layout.fillWidth: true
            Text {
                text: "\u2190"
                color: root.theme.accent
                font.pixelSize: 20
                MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: root.goBack() }
            }
            Text { text: "Settings"; color: root.theme.text; font.pixelSize: 20; font.weight: Font.Medium; Layout.leftMargin: 12 }
        }

        // ---- Appearance ----
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: appearanceCol.implicitHeight + 32
            radius: 14
            color: root.theme.card

            ColumnLayout {
                id: appearanceCol
                anchors.fill: parent
                anchors.margins: 16
                spacing: 14

                Text { text: "Appearance"; color: root.theme.text; font.pixelSize: 15; font.weight: Font.Medium }

                // Dark / Light
                RowLayout {
                    Layout.fillWidth: true
                    Text { text: themeBackend.darkMode ? "\u{1F319}  Dark mode" : "\u2600  Light mode"; color: root.theme.text; font.pixelSize: 14 }
                    Item { Layout.fillWidth: true }
                    Switch {
                        checked: themeBackend.darkMode
                        onToggled: themeBackend.setDarkMode(checked)
                    }
                }

                // Accent color swatches
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Text { text: "Accent color"; color: root.theme.subtext; font.pixelSize: 12 }
                    RowLayout {
                        spacing: 10
                        Repeater {
                            model: ["#7fd6b4", "#5fb3e8", "#e8b25f", "#e87f9f", "#b58fe8", "#8fe86f"]
                            delegate: Rectangle {
                                width: 44; height: 44; radius: 22
                                color: modelData
                                border.width: themeBackend.accentColor === modelData ? 3 : 0
                                border.color: root.theme.text
                                MouseArea { anchors.fill: parent; onClicked: { root.sounds.select(); themeBackend.setAccentColor(modelData) } }
                            }
                        }
                    }
                }

                // Background image
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Text { text: "Background image"; color: root.theme.subtext; font.pixelSize: 12 }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        Text {
                            Layout.fillWidth: true
                            text: themeBackend.backgroundImage !== "" ? "Custom background set" : "None (default color)"
                            color: root.theme.text
                            font.pixelSize: 13
                            elide: Text.ElideRight
                        }
                        Rectangle {
                            Layout.preferredWidth: 84
                            Layout.preferredHeight: 32
                            radius: 10
                            color: storageBackend.storagePresent ? root.theme.cardAlt : "#4a5f57"
                            opacity: storageBackend.storagePresent ? 1.0 : 0.5
                            Text { anchors.centerIn: parent; text: "Choose"; color: "#fff"; font.pixelSize: 12 }
                            MouseArea {
                                anchors.fill: parent
                                enabled: storageBackend.storagePresent
                                onClicked: bgPicker.visible = true
                            }
                        }
                        Rectangle {
                            visible: themeBackend.backgroundImage !== ""
                            Layout.preferredWidth: 64
                            Layout.preferredHeight: 32
                            radius: 10
                            color: "#993c1d"
                            Text { anchors.centerIn: parent; text: "Reset"; color: "#fff"; font.pixelSize: 12 }
                            MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: themeBackend.clearBackgroundImage() }
                        }
                    }
                    Text {
                        visible: !storageBackend.storagePresent
                        text: "Insert a USB/SD card with an image to set a custom background."
                        color: root.theme.subtext
                        font.pixelSize: 10
                    }
                    RowLayout {
                        visible: themeBackend.backgroundImage !== ""
                        Layout.fillWidth: true
                        spacing: 10
                        Text { text: "Strength"; color: root.theme.subtext; font.pixelSize: 12 }
                        Slider {
                            Layout.fillWidth: true
                            from: 0.05
                            to: 0.6
                            value: themeBackend.backgroundOpacity
                            onPressedChanged: if (!pressed) themeBackend.setBackgroundOpacity(value)
                        }
                    }
                    Text {
                        visible: bgPicker.lastError !== ""
                        text: bgPicker.lastError
                        color: "#e8917f"
                        font.pixelSize: 11
                    }
                }
            }
        }

        // ---- Brightness ----
        Rectangle {
            visible: brightnessBackend.available
            Layout.fillWidth: true
            height: 76
            radius: 14
            color: "#173832"

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 6
                RowLayout {
                    Layout.fillWidth: true
                    Image { source: "qrc:/assets/images/brightness_icon.png"; Layout.preferredWidth: 26; Layout.preferredHeight: 26; fillMode: Image.PreserveAspectFit; smooth: true }
                    Text { text: "Brightness"; color: root.theme.text; font.pixelSize: 15; Layout.leftMargin: 4 }
                    Item { Layout.fillWidth: true }
                    Text { text: brightnessBackend.brightness + "%"; color: root.theme.subtext; font.pixelSize: 13 }
                }
                Slider {
                    Layout.fillWidth: true
                    from: 1
                    to: 100
                    stepSize: 1
                    value: brightnessBackend.brightness
                    // Commit on release only - dragging fires a pkexec
                    // write per step on stock permissions otherwise,
                    // which is both slow and prompts repeatedly.
                    onPressedChanged: if (!pressed) brightnessBackend.setBrightness(value)
                }
            }
        }
        Text {
            visible: !brightnessBackend.available
            text: "No backlight device detected on this hardware."
            color: "#6f9585"
            font.pixelSize: 11
        }

        // ---- Volume ----
        Rectangle {
            visible: volumeBackend.available
            Layout.fillWidth: true
            height: 76
            radius: 14
            color: "#173832"

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 6
                RowLayout {
                    Layout.fillWidth: true
                    Image { source: "qrc:/assets/images/volume_icon.png"; Layout.preferredWidth: 26; Layout.preferredHeight: 26; fillMode: Image.PreserveAspectFit; smooth: true }
                    Text {
                        text: volumeBackend.muted ? "Volume (muted)" : "Volume"
                        color: root.theme.text
                        font.pixelSize: 15
                        Layout.leftMargin: 4
                    }
                    Item { Layout.fillWidth: true }
                    Text { text: volumeBackend.muted ? "Muted" : volumeBackend.volume + "%"; color: root.theme.subtext; font.pixelSize: 13 }
                    Switch {
                        checked: volumeBackend.muted
                        onToggled: volumeBackend.setMuted(checked)
                    }
                }
                Slider {
                    Layout.fillWidth: true
                    from: 0
                    to: 100
                    stepSize: 1
                    enabled: !volumeBackend.muted
                    opacity: enabled ? 1.0 : 0.5
                    value: volumeBackend.volume
                    onPressedChanged: if (!pressed) volumeBackend.setVolume(value)
                }
            }
        }
        Text {
            visible: !volumeBackend.available
            text: "No audio control (wpctl) found on this system."
            color: "#6f9585"
            font.pixelSize: 11
        }

        // ---- WiFi toggle row ----
        Rectangle {
            Layout.fillWidth: true
            height: 56
            radius: 14
            color: "#173832"

            RowLayout {
                anchors.fill: parent
                anchors.margins: 16
                Text { text: "WiFi"; color: "#dff2ea"; font.pixelSize: 15 }
                Item { Layout.fillWidth: true }
                Switch {
                    checked: wifiBackend.wifiEnabled
                    onToggled: wifiBackend.setWifiEnabled(checked)
                }
            }
        }

        Text {
            text: wifiBackend.statusMessage
            color: "#8fb3a4"
            font.pixelSize: 12
        }

        // ---- Network list ----
        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: wifiBackend.wifiEnabled
            model: wifiBackend.networks
            spacing: 8
            clip: true

            delegate: Rectangle {
                width: ListView.view.width
                height: 52
                radius: 12
                color: selectedSsid === modelData.ssid ? "#0f6e56" : "#173832"

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    Text { text: modelData.ssid; color: "#dff2ea"; font.pixelSize: 14; Layout.fillWidth: true }
                    Text { text: modelData.secured ? "\ud83d\udd12" : ""; color: "#8fb3a4"; font.pixelSize: 12 }
                    Text { text: modelData.signal + "%"; color: "#8fb3a4"; font.pixelSize: 12 }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        if (modelData.secured) {
                            selectedSsid = modelData.ssid
                            passwordDialog.open()
                        } else {
                            wifiBackend.connectToNetwork(modelData.ssid, "")
                        }
                    }
                }
            }
        }

        // ---- Power controls ----
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Rectangle {
                Layout.fillWidth: true
                height: 48
                radius: 12
                color: "#3c3489"
                Text { anchors.centerIn: parent; text: "Restart"; color: "#fff"; font.pixelSize: 14 }
                MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: { powerAction = "restart"; powerDialog.open() } }
            }
            Rectangle {
                Layout.fillWidth: true
                height: 48
                radius: 12
                color: "#993c1d"
                Text { anchors.centerIn: parent; text: "Shut down"; color: "#fff"; font.pixelSize: 14 }
                MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: { powerAction = "shutdown"; powerDialog.open() } }
            }
        }

        // ---- Account & Security ----
        // Visible in every state: no-accounts (offer to set one up),
        // logged-out-with-accounts (shouldn't really be reachable since
        // LockScreen would be covering the whole app, but handled
        // gracefully anyway), and logged-in (manage users if admin,
        // change own password, auto-lock timing, lock/logout actions).
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: accountCol.implicitHeight + 32
            radius: 14
            color: root.theme.card

            ColumnLayout {
                id: accountCol
                anchors.fill: parent
                anchors.margins: 16
                spacing: 14

                Text { text: "Account & Security"; color: root.theme.text; font.pixelSize: 15; font.weight: Font.Medium }

                // No accounts set up at all yet
                ColumnLayout {
                    visible: !authBackend.hasAccounts
                    Layout.fillWidth: true
                    spacing: 8
                    Text {
                        text: "No login is set up. Anyone can use this device without signing in."
                        color: root.theme.subtext
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 42
                        radius: 12
                        color: root.theme.cardAlt
                        Text { anchors.centerIn: parent; text: "Set Up Account"; color: "#fff"; font.pixelSize: 13 }
                        MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: { accountDialog.isFirstAccount = true; accountDialog.open() } }
                    }
                }

                // Accounts exist - show session + management
                ColumnLayout {
                    visible: authBackend.hasAccounts
                    Layout.fillWidth: true
                    spacing: 12

                    RowLayout {
                        Layout.fillWidth: true
                        visible: authBackend.loggedInUser !== ""
                        Text {
                            Layout.fillWidth: true
                            text: "Signed in as " + authBackend.loggedInUser + (authBackend.loggedInIsAdmin ? " (admin)" : "")
                            color: root.theme.text
                            font.pixelSize: 13
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 40
                            radius: 12
                            color: "#173832"
                            Text { anchors.centerIn: parent; text: "Lock Now"; color: root.theme.text; font.pixelSize: 13 }
                            MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: authBackend.lockNow() }
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 40
                            radius: 12
                            color: "#173832"
                            Text { anchors.centerIn: parent; text: "Log Out"; color: root.theme.text; font.pixelSize: 13 }
                            MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: authBackend.logout() }
                        }
                    }

                    // Auto-lock timing
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Text { text: "Auto-lock after inactivity"; color: root.theme.subtext; font.pixelSize: 12 }
                        RowLayout {
                            spacing: 8
                            Repeater {
                                model: [
                                    { label: "1m", value: 1 },
                                    { label: "5m", value: 5 },
                                    { label: "15m", value: 15 },
                                    { label: "Never", value: 0 }
                                ]
                                delegate: Rectangle {
                                    Layout.preferredWidth: 62
                                    Layout.preferredHeight: 32
                                    radius: 10
                                    color: authBackend.autoLockMinutes === modelData.value ? root.theme.accent : "#173832"
                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.label
                                        color: authBackend.autoLockMinutes === modelData.value ? "#10241f" : root.theme.subtext
                                        font.pixelSize: 12
                                    }
                                    MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: authBackend.setAutoLockMinutes(modelData.value) }
                                }
                            }
                        }
                    }

                    // Change own password
                    Rectangle {
                        visible: authBackend.loggedInUser !== ""
                        Layout.fillWidth: true
                        Layout.preferredHeight: 40
                        radius: 12
                        color: "#173832"
                        Text { anchors.centerIn: parent; text: "Change Password"; color: root.theme.text; font.pixelSize: 13 }
                        MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: { changePassDialog.errorText = ""; oldPassField.text = ""; newPassField.text = ""; changePassDialog.open() } }
                    }

                    // Admin: manage users
                    ColumnLayout {
                        visible: authBackend.loggedInIsAdmin
                        Layout.fillWidth: true
                        spacing: 8

                        Text { text: "Users"; color: root.theme.subtext; font.pixelSize: 12 }

                        Repeater {
                            model: authBackend.loggedInIsAdmin ? authBackend.listUsers() : []
                            delegate: RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.username + (modelData.isAdmin ? " (admin)" : "")
                                    color: root.theme.text
                                    font.pixelSize: 13
                                }
                                Text {
                                    text: "Remove"
                                    color: "#e8917f"
                                    font.pixelSize: 12
                                    visible: modelData.username !== authBackend.loggedInUser || authBackend.listUsers().length > 1
                                    MouseArea {
                                        anchors.fill: parent
                                        anchors.margins: -8
                                        onClicked: { deleteUserDialog.targetUser = modelData.username; deleteUserDialog.errorText = ""; deleteUserDialog.adminPassField.clear(); deleteUserDialog.open() }
                                    }
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 40
                            radius: 12
                            color: root.theme.cardAlt
                            Text { anchors.centerIn: parent; text: "Add User"; color: "#fff"; font.pixelSize: 13 }
                            MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: { accountDialog.isFirstAccount = false; accountDialog.errorText = ""; accountDialog.open() } }
                        }
                    }
                }
            }
        }
    }

    Dialog {
        id: passwordDialog
        anchors.centerIn: parent
        modal: true
        width: 320
        title: "Connect to " + selectedSsid

        contentItem: ColumnLayout {
            spacing: 12
            width: 280
            TextField {
                id: pwField
                placeholderText: "Password"
                echoMode: TextInput.Password
                Layout.fillWidth: true
            }
        }

        footer: DialogButtonBox {
            Button { text: "Cancel"; DialogButtonBox.buttonRole: DialogButtonBox.RejectRole }
            Button { text: "Connect"; DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole }
        }

        onAccepted: wifiBackend.connectToNetwork(selectedSsid, pwField.text)
    }

    Dialog {
        id: powerDialog
        anchors.centerIn: parent
        modal: true
        width: 320
        title: powerAction === "restart" ? "Restart device?" : "Shut down device?"

        contentItem: Text {
            text: powerAction === "restart"
                ? "The device will restart immediately."
                : "The device will power off immediately."
            color: "#dff2ea"
            width: 260
            wrapMode: Text.WordWrap
        }

        footer: DialogButtonBox {
            Button { text: "Cancel"; DialogButtonBox.buttonRole: DialogButtonBox.RejectRole }
            Button {
                text: powerAction === "restart" ? "Restart" : "Shut down"
                DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
            }
        }

        onAccepted: {
            if (powerAction === "restart") powerBackend.restart()
            else powerBackend.shutdown()
        }
    }

    // ---- Account creation: handles both "first account ever" (from the
    // no-accounts-yet prompt) and "admin adding another user". Uses a
    // plain button instead of DialogButtonBox's AcceptRole so a
    // validation failure (bad password, duplicate username) can show an
    // inline error and keep the dialog open, rather than closing
    // regardless of the result the way the WiFi/power dialogs above do.
    Dialog {
        id: accountDialog
        anchors.centerIn: parent
        modal: true
        width: 320
        property bool isFirstAccount: false
        property string errorText: ""
        title: isFirstAccount ? "Set Up Account" : "Add User"
        onOpened: { newUserField.text = ""; newUserPass1.text = ""; newUserPass2.text = ""; newUserAdmin.checked = false; errorText = "" }

        contentItem: ColumnLayout {
            spacing: 10
            width: 280
            TextField { id: newUserField; placeholderText: "Username"; Layout.fillWidth: true }
            TextField { id: newUserPass1; placeholderText: "Password (min. 4 characters)"; echoMode: TextInput.Password; Layout.fillWidth: true }
            TextField { id: newUserPass2; placeholderText: "Confirm password"; echoMode: TextInput.Password; Layout.fillWidth: true }
            RowLayout {
                visible: !accountDialog.isFirstAccount
                Layout.fillWidth: true
                Text { text: "Make this user an admin"; color: "#dff2ea"; font.pixelSize: 12; Layout.fillWidth: true }
                Switch { id: newUserAdmin }
            }
            Text {
                visible: accountDialog.errorText !== ""
                text: accountDialog.errorText
                color: "#e8917f"
                font.pixelSize: 11
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
        }

        footer: DialogButtonBox {
            Button { text: "Cancel"; DialogButtonBox.buttonRole: DialogButtonBox.RejectRole }
            Button {
                text: accountDialog.isFirstAccount ? "Create" : "Add"
                onClicked: {
                    if (newUserPass1.text !== newUserPass2.text) {
                        accountDialog.errorText = "Passwords don't match."
                        return
                    }
                    var isAdmin = accountDialog.isFirstAccount ? true : newUserAdmin.checked
                    var res = authBackend.createAccount(newUserField.text, newUserPass1.text, isAdmin)
                    if (res.ok) {
                        accountDialog.close()
                        // First account created: log straight in so the
                        // person doesn't have to immediately re-enter
                        // credentials at a lock screen they just set up.
                        if (accountDialog.isFirstAccount) {
                            authBackend.login(newUserField.text, newUserPass1.text)
                        }
                    } else {
                        accountDialog.errorText = res.error
                    }
                }
            }
        }
    }

    // ---- Change own password ----
    Dialog {
        id: changePassDialog
        anchors.centerIn: parent
        modal: true
        width: 320
        property string errorText: ""
        title: "Change Password"

        contentItem: ColumnLayout {
            spacing: 10
            width: 280
            TextField { id: oldPassField; placeholderText: "Current password"; echoMode: TextInput.Password; Layout.fillWidth: true }
            TextField { id: newPassField; placeholderText: "New password (min. 4 characters)"; echoMode: TextInput.Password; Layout.fillWidth: true }
            Text {
                visible: changePassDialog.errorText !== ""
                text: changePassDialog.errorText
                color: "#e8917f"
                font.pixelSize: 11
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
        }

        footer: DialogButtonBox {
            Button { text: "Cancel"; DialogButtonBox.buttonRole: DialogButtonBox.RejectRole }
            Button {
                text: "Save"
                onClicked: {
                    var res = authBackend.changePassword(authBackend.loggedInUser, oldPassField.text, newPassField.text)
                    if (res.ok) {
                        changePassDialog.close()
                    } else {
                        changePassDialog.errorText = res.error
                    }
                }
            }
        }
    }

    // ---- Delete user (admin-only, re-verifies the ACTING admin's own
    // password server-side - see AuthBackend::deleteAccount) ----
    Dialog {
        id: deleteUserDialog
        anchors.centerIn: parent
        modal: true
        width: 320
        property string targetUser: ""
        property string errorText: ""
        property alias adminPassField: delPassField
        title: "Remove " + targetUser + "?"

        contentItem: ColumnLayout {
            spacing: 10
            width: 280
            Text {
                text: "Enter your admin password to confirm."
                color: "#dff2ea"
                font.pixelSize: 12
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
            TextField { id: delPassField; placeholderText: "Your password"; echoMode: TextInput.Password; Layout.fillWidth: true }
            Text {
                visible: deleteUserDialog.errorText !== ""
                text: deleteUserDialog.errorText
                color: "#e8917f"
                font.pixelSize: 11
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
        }

        footer: DialogButtonBox {
            Button { text: "Cancel"; DialogButtonBox.buttonRole: DialogButtonBox.RejectRole }
            Button {
                text: "Remove"
                onClicked: {
                    var res = authBackend.deleteAccount(deleteUserDialog.targetUser, delPassField.text)
                    if (res.ok) {
                        deleteUserDialog.close()
                    } else {
                        deleteUserDialog.errorText = res.error
                    }
                }
            }
        }
    }

    // ---- Background image picker: a lightweight inline browser over
    // the current storage device, reusing dbConnectorBackend.listDirectory
    // (already generic - same call DatabaseConnector.qml makes) and
    // filtering client-side to image-looking extensions. Deliberately
    // its own small overlay rather than a full "installer"-esque
    // navigateTo() screen, since picking a background is a two-tap
    // in-and-out action from Settings, not a destination in its own
    // right.
    Rectangle {
        id: bgPicker
        anchors.fill: parent
        visible: false
        color: "#0a1815"
        opacity: visible ? 0.97 : 0
        z: 2000

        property string currentPath: storageBackend.devices.length > 0 ? storageBackend.devices[0].path : "/media"
        property var pathStack: []
        property string lastError: ""
        readonly property var imageExts: ["jpg", "jpeg", "png", "bmp", "gif", "webp"]
        readonly property var listing: visible ? dbConnectorBackend.listDirectory(currentPath) : []
        function isImage(name) {
            var dot = name.lastIndexOf(".")
            if (dot < 0) return false
            return imageExts.indexOf(name.substring(dot + 1).toLowerCase()) !== -1
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 14

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "\u2715"
                    color: root.theme.accent
                    font.pixelSize: 18
                    MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: bgPicker.visible = false }
                }
                Text { text: "Choose a background image"; color: "#e8f5ee"; font.pixelSize: 17; font.weight: Font.Medium; Layout.leftMargin: 12 }
            }
            Text {
                text: bgPicker.currentPath
                color: "#8fb3a4"
                font.pixelSize: 11
                elide: Text.ElideMiddle
                Layout.maximumWidth: 500
            }

            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 8
                model: bgPicker.listing

                delegate: Rectangle {
                    width: ListView.view.width
                    height: 56
                    radius: 12
                    color: "#173832"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 12
                        Text {
                            text: modelData.isDir ? "\u{1F4C1}" : (bgPicker.isImage(modelData.name) ? "\u{1F5BC}" : "\u2022")
                            color: "#7fd6b4"
                            font.pixelSize: 16
                        }
                        Text { text: modelData.name; color: "#dff2ea"; font.pixelSize: 13; elide: Text.ElideRight; Layout.fillWidth: true }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            if (modelData.isDir) {
                                bgPicker.pathStack.push(bgPicker.currentPath)
                                bgPicker.currentPath = modelData.path
                            } else if (bgPicker.isImage(modelData.name)) {
                                var res = themeBackend.setBackgroundImage(modelData.path)
                                if (res.ok) {
                                    bgPicker.lastError = ""
                                    bgPicker.visible = false
                                } else {
                                    bgPicker.lastError = res.error
                                }
                            }
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: bgPicker.listing.length === 0
                    text: "Nothing here"
                    color: "#5f8579"
                    font.pixelSize: 13
                }
            }

            Rectangle {
                visible: bgPicker.pathStack.length > 0
                Layout.preferredWidth: 90
                Layout.preferredHeight: 34
                radius: 10
                color: "#173832"
                Text { anchors.centerIn: parent; text: "\u2190 Back"; color: "#dff2ea"; font.pixelSize: 12 }
                MouseArea {
                    anchors.fill: parent
                    onClicked: bgPicker.currentPath = bgPicker.pathStack.pop()
                }
            }
        }
    }
}
