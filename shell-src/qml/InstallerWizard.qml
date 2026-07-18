import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15

// "Install RoohaniyeNooreIlm" wizard. Only reachable from the home-screen
// banner, which itself only shows while !installerBackend.isInstalled().
// Steps: welcome -> pick disk -> customize databases (optional) -> review
// & confirm ("type ERASE") -> progress -> done/error.
// Every destructive step is gated: Continue/Install buttons stay disabled
// until their step's precondition is actually met (disk picked, "ERASE"
// typed exactly) - never just visually suggested.
Rectangle {
    id: wiz
    anchors.fill: parent
    color: "#10241f"

    // 0 welcome, 1 disk, 2 databases, 3 account (optional), 4 review,
    // 5 progress, 6 result
    property int step: 0
    property var selectedDisk: null
    property var extraDbs: []   // [{ sourcePath, targetFile, name, sizeLabel }]
    property string confirmInput: ""
    property string currentDir: "/media"
    property string pickingTargetFile: "" // which db slot the browser overlay is filling
    property bool browsing: false

    // ---- Optional "create an account" step. Off by default (a Try/
    // install session should never be forced into setting up a login) -
    // toggling it on and filling in valid details stages a real
    // accounts.dat that gets copied onto the TARGET disk only, never
    // touching this live session's own login state. ----
    property bool accountEnabled: false
    property string acctUsername: ""
    property string acctPassword: ""
    property string acctPasswordConfirm: ""
    property string acctError: ""
    property string acctRecoveryCode: "" // filled in once installerBackend confirms the export succeeded

    property int progressPercent: 0
    property string progressStage: ""
    property var logLines: []
    property bool installOk: false
    property string installError: ""

    function refreshDisks() { diskModel.items = installerBackend.listDisks() }
    function refreshDir(path) {
        currentDir = path
        dirModel.items = installerBackend.listDirectory(path)
    }

    QtObject { id: diskModel; property var items: [] }
    QtObject { id: dirModel; property var items: [] }

    Connections {
        target: installerBackend
        function onInstallProgress(percent, stage, detail) {
            wiz.progressPercent = percent
            wiz.progressStage = stage
        }
        function onInstallLog(line) {
            var l = wiz.logLines.slice()
            l.push(line)
            if (l.length > 200) l = l.slice(l.length - 200)
            wiz.logLines = l
        }
        function onInstallFinished(ok, error) {
            wiz.installOk = ok
            wiz.installError = error
            wiz.step = 6
        }
    }

    Component.onCompleted: refreshDisks()

    Connections {
        target: installerBackend
        function onInstallAccountRecoveryCode(username, code) {
            wiz.acctRecoveryCode = code
        }
    }

    // ---------- top bar ----------
    RowLayout {
        id: topBar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 24
        height: 30
        visible: step < 5 || (step === 6)

        Text {
            text: "\u2190"
            color: "#7fd6b4"
            font.pixelSize: 20
            visible: step === 0
            MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: root.currentView = "home" }
        }
        Text {
            text: "\u2190 Back"
            color: "#7fd6b4"
            font.pixelSize: 16
            visible: step > 0 && step < 5
            MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: wiz.step -= 1 }
        }
        Text {
            text: "Install RoohaniyeNooreIlm"
            color: "#e8f5ee"
            font.pixelSize: 18
            font.weight: Font.Medium
            Layout.leftMargin: 12
        }
        Item { Layout.fillWidth: true }
        Text {
            visible: step > 0 && step < 5
            text: "Step " + step + " of 4"
            color: "#6f9585"
            font.pixelSize: 12
        }
    }

    // ---------- step content ----------
    Item {
        anchors.top: topBar.bottom
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: 12

        // ===== STEP 0: welcome =====
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 28
            spacing: 18
            visible: wiz.step === 0
            opacity: wiz.step === 0 ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 220 } }

            Item { Layout.preferredHeight: 12 }
            Text {
                text: "\u2726"
                color: "#7fd6b4"
                font.pixelSize: 40
                Layout.alignment: Qt.AlignHCenter
            }
            Text {
                text: "Install RoohaniyeNooreIlm"
                color: "#e8f5ee"
                font.pixelSize: 24
                font.weight: Font.Medium
                Layout.alignment: Qt.AlignHCenter
            }
            Text {
                text: "You're currently running the live/try session. Installing puts RoohaniyeNooreIlm permanently on a disk of your choice, so it boots straight in every time \u2014 no USB needed."
                color: "#8fb3a4"
                font.pixelSize: 14
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignHCenter
                Layout.maximumWidth: 520
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.maximumWidth: 520
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredHeight: infoCol.height + 28
                radius: 16
                color: "#173832"
                ColumnLayout {
                    id: infoCol
                    x: 18; y: 14
                    width: parent.width - 36
                    spacing: 10
                    Repeater {
                        model: [
                            "Every disk you own will be listed with its real size and model \u2014 nothing is picked for you.",
                            "The disk currently running this live session is never shown, so you can't accidentally erase it.",
                            "You can bring your own quran_audio.db / quran_text.db / hadiths.db from a USB drive to use instead of the ones on the live image.",
                            "Nothing is touched until you type ERASE exactly on the confirmation screen.",
                            "This only appears once \u2014 after a successful install, this app won't offer itself again."
                        ]
                        delegate: RowLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            Text { text: "\u2022"; color: "#7fd6b4"; font.pixelSize: 14 }
                            Text {
                                text: modelData
                                color: "#bfe9d8"
                                font.pixelSize: 13
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }
                        }
                    }
                }
            }

            Item { Layout.fillHeight: true }

            Rectangle {
                Layout.fillWidth: true
                Layout.maximumWidth: 520
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredHeight: 50
                radius: 12
                color: "#0f6e56"
                Text { anchors.centerIn: parent; text: "Get started"; color: "#fff"; font.pixelSize: 15; font.weight: Font.Medium }
                MouseArea {
                    anchors.fill: parent
                    onClicked: { wiz.refreshDisks(); wiz.step = 1 }
                }
            }
            Text {
                text: "Not now"
                color: "#6f9585"
                font.pixelSize: 13
                Layout.alignment: Qt.AlignHCenter
                Layout.bottomMargin: 8
                MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: root.currentView = "home" }
            }
        }

        // ===== STEP 1: disk selection =====
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 28
            spacing: 14
            visible: wiz.step === 1
            opacity: wiz.step === 1 ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 220 } }

            Text { text: "Choose a disk"; color: "#e8f5ee"; font.pixelSize: 20; font.weight: Font.Medium }
            Text {
                text: "This disk will be completely erased and used only for RoohaniyeNooreIlm. Your live session's own disk is never listed."
                color: "#8fb3a4"; font.pixelSize: 13; wrapMode: Text.WordWrap; Layout.fillWidth: true
            }

            RowLayout {
                Layout.fillWidth: true
                Text { text: diskModel.items.length + " disk(s) found"; color: "#6f9585"; font.pixelSize: 12 }
                Item { Layout.fillWidth: true }
                Text {
                    text: "\u27F3 Refresh"
                    color: "#7fd6b4"
                    font.pixelSize: 12
                    MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: wiz.refreshDisks() }
                }
            }

            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentHeight: diskCol.height
                clip: true

                ColumnLayout {
                    id: diskCol
                    width: parent.width
                    spacing: 10

                    Text {
                        visible: diskModel.items.length === 0
                        text: "No eligible disks found. Plug in a drive (or if this is a single-disk machine, note it's excluded because it's the one currently running this live session)."
                        color: "#6f9585"; font.pixelSize: 13; wrapMode: Text.WordWrap; Layout.fillWidth: true
                        Layout.topMargin: 20
                    }

                    Repeater {
                        model: diskModel.items
                        delegate: Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 84
                            radius: 14
                            readonly property bool isSelected: wiz.selectedDisk && wiz.selectedDisk.path === modelData.path
                            color: isSelected ? "#0f6e56" : "#173832"
                            border.width: isSelected ? 2 : 0
                            border.color: "#7fd6b4"
                            Behavior on color { ColorAnimation { duration: 150 } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 16
                                spacing: 14

                                Rectangle {
                                    width: 44; height: 44; radius: 10
                                    color: isSelected ? "#0a4e3d" : "#10241f"
                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.transport === "usb" ? "\u{1F5B4}" : "\u25A6"
                                        font.pixelSize: 18
                                    }
                                }

                                ColumnLayout {
                                    spacing: 2
                                    Layout.fillWidth: true
                                    Text { text: modelData.model + "  (" + modelData.name + ")"; color: "#e8f5ee"; font.pixelSize: 14; font.weight: Font.Medium }
                                    Text {
                                        text: modelData.sizeLabel + " \u00B7 " + modelData.transport.toUpperCase() + (modelData.isRemovable ? " \u00B7 removable" : "")
                                        color: "#8fb3a4"; font.pixelSize: 12
                                    }
                                }

                                Text { visible: isSelected; text: "\u2713"; color: "#fff"; font.pixelSize: 18 }
                            }

                            MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: wiz.selectedDisk = modelData }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 50
                radius: 12
                color: wiz.selectedDisk ? "#0f6e56" : "#20463d"
                opacity: wiz.selectedDisk ? 1.0 : 0.6
                Text { anchors.centerIn: parent; text: "Continue"; color: "#fff"; font.pixelSize: 15; font.weight: Font.Medium }
                MouseArea { anchors.fill: parent; enabled: !!wiz.selectedDisk; onClicked: wiz.step = 2 }
            }
        }

        // ===== STEP 2: database customization =====
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 28
            spacing: 14
            visible: wiz.step === 2
            opacity: wiz.step === 2 ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 220 } }

            Text { text: "Customize databases (optional)"; color: "#e8f5ee"; font.pixelSize: 20; font.weight: Font.Medium }
            Text {
                text: "The install already includes everything on this live image. If you have fuller replacements on a USB drive \u2014 a bigger quran_audio.db, corrected quran_text.db, or an extended hadiths.db \u2014 pick them here and they'll overwrite the defaults after install."
                color: "#8fb3a4"; font.pixelSize: 13; wrapMode: Text.WordWrap; Layout.fillWidth: true
            }

            Repeater {
                model: [
                    { key: "quran_text.db", label: "Quran text database" },
                    { key: "quran_audio.db", label: "Quran audio database" },
                    { key: "hadiths.db", label: "Hadith database" }
                ]
                delegate: Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 64
                    radius: 14
                    color: "#173832"

                    property var picked: {
                        for (var i = 0; i < wiz.extraDbs.length; i++)
                            if (wiz.extraDbs[i].targetFile === modelData.key) return wiz.extraDbs[i]
                        return null
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 12
                        ColumnLayout {
                            spacing: 2
                            Layout.fillWidth: true
                            Text { text: modelData.label; color: "#e8f5ee"; font.pixelSize: 14 }
                            Text {
                                text: picked ? ("Using: " + picked.name + " (" + picked.sizeLabel + ")") : "Using the version already on this image"
                                color: picked ? "#7fd6b4" : "#6f9585"
                                font.pixelSize: 11
                                elide: Text.ElideMiddle
                                Layout.fillWidth: true
                            }
                        }
                        Text {
                            text: picked ? "Change" : "Browse\u2026"
                            color: "#7fd6b4"; font.pixelSize: 13
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    wiz.pickingTargetFile = modelData.key
                                    wiz.refreshDir("/media")
                                    wiz.browsing = true
                                }
                            }
                        }
                        Text {
                            visible: !!picked
                            text: "\u2715"
                            color: "#c98a8a"; font.pixelSize: 13
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    var l = wiz.extraDbs.filter(function(d) { return d.targetFile !== modelData.key })
                                    wiz.extraDbs = l
                                }
                            }
                        }
                    }
                }
            }

            Item { Layout.fillHeight: true }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 50
                radius: 12
                color: "#0f6e56"
                Text { anchors.centerIn: parent; text: "Continue"; color: "#fff"; font.pixelSize: 15; font.weight: Font.Medium }
                MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: wiz.step = 3 }
            }
        }

        // ===== STEP 3: account (optional) =====
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 28
            spacing: 14
            visible: wiz.step === 3
            opacity: wiz.step === 3 ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 220 } }

            Text { text: "Set up an account (optional)"; color: "#e8f5ee"; font.pixelSize: 20; font.weight: Font.Medium }
            Text {
                text: "Leave this off and the installed system boots straight in, unlocked, same as the live session \u2014 you can always add an account later from Settings. Turn it on to require sign-in from first boot."
                color: "#8fb3a4"; font.pixelSize: 13; wrapMode: Text.WordWrap; Layout.fillWidth: true
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 56
                radius: 14
                color: "#173832"
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    Text { text: "Require sign-in on this install"; color: "#e8f5ee"; font.pixelSize: 14; Layout.fillWidth: true }
                    Switch {
                        checked: wiz.accountEnabled
                        onToggled: { wiz.accountEnabled = checked; wiz.acctError = "" }
                    }
                }
            }

            ColumnLayout {
                visible: wiz.accountEnabled
                Layout.fillWidth: true
                spacing: 10

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48
                    radius: 12
                    color: "#173832"
                    border.width: 1
                    border.color: "#2c5148"
                    TextInput {
                        anchors.fill: parent
                        anchors.margins: 14
                        color: "#e8f5ee"
                        font.pixelSize: 15
                        verticalAlignment: TextInput.AlignVCenter
                        onTextChanged: wiz.acctUsername = text
                        Text { text: "Username"; color: "#6f9585"; font.pixelSize: 14; visible: parent.text.length === 0; anchors.verticalCenter: parent.verticalCenter }
                    }
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48
                    radius: 12
                    color: "#173832"
                    border.width: 1
                    border.color: "#2c5148"
                    TextInput {
                        anchors.fill: parent
                        anchors.margins: 14
                        color: "#e8f5ee"
                        font.pixelSize: 15
                        echoMode: TextInput.Password
                        verticalAlignment: TextInput.AlignVCenter
                        onTextChanged: wiz.acctPassword = text
                        Text { text: "Password (min 4 characters)"; color: "#6f9585"; font.pixelSize: 14; visible: parent.text.length === 0; anchors.verticalCenter: parent.verticalCenter }
                    }
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48
                    radius: 12
                    color: "#173832"
                    border.width: 1
                    border.color: "#2c5148"
                    TextInput {
                        anchors.fill: parent
                        anchors.margins: 14
                        color: "#e8f5ee"
                        font.pixelSize: 15
                        echoMode: TextInput.Password
                        verticalAlignment: TextInput.AlignVCenter
                        onTextChanged: wiz.acctPasswordConfirm = text
                        Text { text: "Confirm password"; color: "#6f9585"; font.pixelSize: 14; visible: parent.text.length === 0; anchors.verticalCenter: parent.verticalCenter }
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: "This account is created as an admin. A one-time recovery code will be shown after install completes \u2014 write it down, it's the only way back in if the password is forgotten (no email/SMS on this device)."
                    color: "#6f9585"; font.pixelSize: 11; wrapMode: Text.WordWrap
                }
                Text {
                    visible: wiz.acctError !== ""
                    text: wiz.acctError
                    color: "#f2a3a3"; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true
                }
            }

            Item { Layout.fillHeight: true }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 50
                radius: 12
                color: "#0f6e56"
                Text { anchors.centerIn: parent; text: "Continue"; color: "#fff"; font.pixelSize: 15; font.weight: Font.Medium }
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        if (wiz.accountEnabled) {
                            if (wiz.acctUsername.trim() === "") { wiz.acctError = "Enter a username."; return }
                            if (wiz.acctPassword.length < 4) { wiz.acctError = "Password must be at least 4 characters."; return }
                            if (wiz.acctPassword !== wiz.acctPasswordConfirm) { wiz.acctError = "Passwords don't match."; return }
                        }
                        wiz.acctError = ""
                        wiz.step = 4
                    }
                }
            }
        }

        // ===== STEP 4: review & confirm =====
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 28
            spacing: 16
            visible: wiz.step === 4
            opacity: wiz.step === 4 ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 220 } }

            Text { text: "Review \u2014 this cannot be undone"; color: "#f2c9a3"; font.pixelSize: 20; font.weight: Font.Medium }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: reviewCol.height + 28
                radius: 16
                color: "#173832"
                ColumnLayout {
                    id: reviewCol
                    x: 16; y: 14
                    width: parent.width - 32
                    spacing: 8
                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: "Target disk"; color: "#8fb3a4"; font.pixelSize: 12; Layout.preferredWidth: 140 }
                        Text {
                            text: wiz.selectedDisk ? (wiz.selectedDisk.model + " \u2014 " + wiz.selectedDisk.path + " (" + wiz.selectedDisk.sizeLabel + ")") : "\u2014"
                            color: "#e8f5ee"; font.pixelSize: 13; Layout.fillWidth: true; wrapMode: Text.WordWrap
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: "Extra databases"; color: "#8fb3a4"; font.pixelSize: 12; Layout.preferredWidth: 140 }
                        Text {
                            text: wiz.extraDbs.length === 0 ? "None \u2014 using image defaults" : wiz.extraDbs.length + " custom file(s) selected"
                            color: "#e8f5ee"; font.pixelSize: 13; Layout.fillWidth: true; wrapMode: Text.WordWrap
                        }
                    }
                    Repeater {
                        model: wiz.extraDbs
                        delegate: Text {
                            text: "  \u2022 " + modelData.targetFile + " \u2190 " + modelData.name
                            color: "#7fd6b4"; font.pixelSize: 12
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: "Account"; color: "#8fb3a4"; font.pixelSize: 12; Layout.preferredWidth: 140 }
                        Text {
                            text: wiz.accountEnabled ? ("Sign-in required \u2014 \"" + wiz.acctUsername + "\" (admin)") : "None \u2014 boots unlocked, same as this live session"
                            color: "#e8f5ee"; font.pixelSize: 13; Layout.fillWidth: true; wrapMode: Text.WordWrap
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: warnCol.height + 24
                radius: 14
                color: "#3a1f1f"
                border.width: 1
                border.color: "#8a4040"
                ColumnLayout {
                    id: warnCol
                    x: 14; y: 12
                    width: parent.width - 28
                    spacing: 4
                    Text { text: "\u26A0 Everything currently on " + (wiz.selectedDisk ? wiz.selectedDisk.path : "the selected disk") + " will be permanently erased."; color: "#f2a3a3"; font.pixelSize: 13; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                    Text { text: "Type ERASE below (exactly, all caps) to enable the install button."; color: "#e0b3b3"; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 48
                radius: 12
                color: "#173832"
                border.width: 1
                border.color: wiz.confirmInput === "ERASE" ? "#7fd6b4" : "#2c5148"
                TextInput {
                    id: confirmField
                    anchors.fill: parent
                    anchors.margins: 14
                    color: "#e8f5ee"
                    font.pixelSize: 16
                    verticalAlignment: TextInput.AlignVCenter
                    onTextChanged: wiz.confirmInput = text
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Type ERASE to confirm"
                        color: "#6f9585"
                        font.pixelSize: 14
                        visible: confirmField.text.length === 0
                    }
                }
            }

            Item { Layout.fillHeight: true }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 52
                radius: 12
                readonly property bool ready: wiz.confirmInput === "ERASE" && wiz.selectedDisk
                color: ready ? "#8a2f2f" : "#2c1e1e"
                opacity: ready ? 1.0 : 0.6
                Behavior on color { ColorAnimation { duration: 150 } }
                Text { anchors.centerIn: parent; text: "Erase disk & install"; color: "#fff"; font.pixelSize: 15; font.weight: Font.Medium }
                MouseArea {
                    anchors.fill: parent
                    enabled: parent.ready
                    onClicked: {
                        wiz.progressPercent = 0
                        wiz.progressStage = "partitioning"
                        wiz.logLines = []
                        wiz.step = 5
                        var opts = {
                            diskPath: wiz.selectedDisk.path,
                            confirmText: wiz.confirmInput,
                            extraDatabases: wiz.extraDbs
                        }
                        if (wiz.accountEnabled) {
                            opts.account = {
                                username: wiz.acctUsername,
                                password: wiz.acctPassword,
                                isAdmin: true
                            }
                        }
                        installerBackend.startInstall(opts)
                    }
                }
            }
        }

        // ===== STEP 5: progress =====
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 28
            spacing: 22
            visible: wiz.step === 5
            opacity: wiz.step === 5 ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 220 } }

            Item { Layout.preferredHeight: 20 }

            Text {
                text: "Installing RoohaniyeNooreIlm"
                color: "#e8f5ee"; font.pixelSize: 20; font.weight: Font.Medium
                Layout.alignment: Qt.AlignHCenter
            }

            // Spinning ring, purely decorative but communicates "working"
            Item {
                Layout.preferredWidth: 96
                Layout.preferredHeight: 96
                Layout.alignment: Qt.AlignHCenter
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: "transparent"
                    border.width: 6
                    border.color: "#173832"
                }
                Rectangle {
                    id: spinnerArc
                    anchors.fill: parent
                    radius: width / 2
                    color: "transparent"
                    border.width: 6
                    border.color: "#7fd6b4"
                    opacity: 0.9
                    RotationAnimation on rotation {
                        loops: Animation.Infinite
                        from: 0; to: 360
                        duration: 1100
                    }
                }
                Text {
                    anchors.centerIn: parent
                    text: wiz.progressPercent + "%"
                    color: "#e8f5ee"
                    font.pixelSize: 18
                    font.weight: Font.Medium
                }
            }

            Text {
                text: {
                    switch (wiz.progressStage) {
                        case "partitioning": return "Partitioning disk\u2026"
                        case "formatting": return "Formatting partitions\u2026"
                        case "cloning": return "Copying system files\u2026 (this is the slow part)"
                        case "databases": return "Installing databases\u2026"
                        case "bootloader": return "Installing bootloader\u2026"
                        case "finishing": return "Finishing up\u2026"
                        case "done": return "Done"
                        default: return "Starting\u2026"
                    }
                }
                color: "#8fb3a4"; font.pixelSize: 14
                Layout.alignment: Qt.AlignHCenter
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 8
                radius: 4
                color: "#173832"
                Rectangle {
                    height: parent.height
                    radius: 4
                    color: "#0f6e56"
                    width: parent.width * (wiz.progressPercent / 100)
                    Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 14
                color: "#0c1c17"
                clip: true
                Flickable {
                    id: logFlick
                    anchors.fill: parent
                    anchors.margins: 12
                    contentHeight: logCol.height
                    clip: true
                    onContentHeightChanged: contentY = Math.max(0, contentHeight - height)
                    ColumnLayout {
                        id: logCol
                        width: parent.width
                        spacing: 2
                        Repeater {
                            model: wiz.logLines
                            delegate: Text {
                                text: modelData
                                color: "#5f8578"
                                font.pixelSize: 10
                                font.family: "monospace"
                                wrapMode: Text.WrapAnywhere
                                Layout.fillWidth: true
                            }
                        }
                    }
                }
            }

            Text {
                text: "Do not power off or unplug the target disk during install."
                color: "#c98a8a"
                font.pixelSize: 12
                Layout.alignment: Qt.AlignHCenter
            }
        }

        // ===== STEP 6: result =====
        ColumnLayout {
            id: resultStep
            anchors.fill: parent
            anchors.margins: 28
            spacing: 18
            visible: wiz.step === 6
            opacity: wiz.step === 6 ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 220 } }

            property bool usbRemoved: false

            Item { Layout.preferredHeight: 30 }

            Text {
                text: wiz.installOk ? "\u2713" : "\u2715"
                color: wiz.installOk ? "#7fd6b4" : "#f2a3a3"
                font.pixelSize: 46
                Layout.alignment: Qt.AlignHCenter
                scale: 0.6
                Component.onCompleted: scale = 1.0
                Behavior on scale { NumberAnimation { duration: 320; easing.type: Easing.OutBack } }
            }

            Text {
                text: wiz.installOk ? "Installed successfully" : "Install did not complete"
                color: "#e8f5ee"; font.pixelSize: 20; font.weight: Font.Medium
                Layout.alignment: Qt.AlignHCenter
            }

            Text {
                text: wiz.installOk
                    ? "RoohaniyeNooreIlm is now on " + (wiz.selectedDisk ? wiz.selectedDisk.path : "the disk") + ". Remove the install USB drive, then restart to boot straight into it."
                    : wiz.installError
                color: "#8fb3a4"; font.pixelSize: 14
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                Layout.fillWidth: true
                Layout.maximumWidth: 480
                Layout.alignment: Qt.AlignHCenter
            }

            ColumnLayout {
                visible: wiz.installOk && wiz.accountEnabled && wiz.acctRecoveryCode !== ""
                Layout.alignment: Qt.AlignHCenter
                Layout.maximumWidth: 480
                Layout.fillWidth: true
                spacing: 6
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: recoveryCol.height + 24
                    radius: 14
                    color: "#173832"
                    border.width: 1
                    border.color: "#7fd6b4"
                    ColumnLayout {
                        id: recoveryCol
                        x: 16; y: 12
                        width: parent.width - 32
                        spacing: 6
                        Text {
                            text: "Save this recovery code for \"" + wiz.acctUsername + "\" \u2014 it's the only way back in if the password is forgotten:"
                            color: "#bfe9d8"; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true
                        }
                        Text {
                            text: wiz.acctRecoveryCode
                            color: "#7fd6b4"; font.pixelSize: 18; font.weight: Font.Bold; font.family: "monospace"
                            Layout.alignment: Qt.AlignHCenter
                        }
                    }
                }
            }

            // "Remove the USB, then confirm" gate before offering an
            // actual restart - a real reboot with the install media
            // still plugged in risks booting back into the live USB
            // instead of the freshly-installed disk on some firmware,
            // so this is a deliberate, explicit checkpoint rather than
            // a silent auto-reboot.
            Rectangle {
                visible: wiz.installOk
                Layout.fillWidth: true
                Layout.maximumWidth: 480
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredHeight: usbRow.height + 24
                radius: 14
                color: "#173832"
                border.width: 1
                border.color: resultStep.usbRemoved ? "#7fd6b4" : "#2c5148"
                RowLayout {
                    id: usbRow
                    x: 16; y: 12
                    width: parent.width - 32
                    spacing: 12
                    Rectangle {
                        width: 26; height: 26; radius: 7
                        color: resultStep.usbRemoved ? "#0f6e56" : "transparent"
                        border.width: 2
                        border.color: "#7fd6b4"
                        Text { anchors.centerIn: parent; text: "\u2713"; color: "#fff"; font.pixelSize: 15; visible: resultStep.usbRemoved }
                        MouseArea { anchors.fill: parent; anchors.margins: -9; onClicked: resultStep.usbRemoved = !resultStep.usbRemoved }
                    }
                    Text {
                        text: "I've removed the USB drive"
                        color: "#e8f5ee"; font.pixelSize: 14
                        Layout.fillWidth: true
                        MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: resultStep.usbRemoved = !resultStep.usbRemoved }
                    }
                }
            }

            Item { Layout.fillHeight: true }

            RowLayout {
                Layout.fillWidth: true
                Layout.maximumWidth: 480
                Layout.alignment: Qt.AlignHCenter
                spacing: 10

                Rectangle {
                    visible: wiz.installOk
                    Layout.fillWidth: true
                    Layout.preferredHeight: 50
                    radius: 12
                    readonly property bool ready: resultStep.usbRemoved
                    color: ready ? "#8a2f2f" : "#2c1e1e"
                    opacity: ready ? 1.0 : 0.55
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Text { anchors.centerIn: parent; text: "Restart now"; color: "#fff"; font.pixelSize: 15; font.weight: Font.Medium }
                    MouseArea {
                        anchors.fill: parent
                        enabled: parent.ready
                        onClicked: installerBackend.rebootSystem()
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 50
                    radius: 12
                    color: wiz.installOk ? "#173832" : "#0f6e56"
                    Text {
                        anchors.centerIn: parent
                        text: wiz.installOk ? "Later, back to home" : "Try again"
                        color: wiz.installOk ? "#7fd6b4" : "#fff"
                        font.pixelSize: 15; font.weight: Font.Medium
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            if (wiz.installOk) {
                                root.currentView = "home"
                            } else {
                                wiz.step = 4
                            }
                        }
                    }
                }
            }
        }
    }

    // ---------- USB file browser overlay (step 2 only) ----------
    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: wiz.browsing ? 0.55 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 180 } }
        MouseArea { anchors.fill: parent; onClicked: wiz.browsing = false }
    }

    Rectangle {
        id: browserPanel
        anchors.centerIn: parent
        width: Math.min(560, wiz.width - 60)
        height: Math.min(460, wiz.height - 60)
        radius: 18
        color: "#173832"
        visible: wiz.browsing
        opacity: wiz.browsing ? 1 : 0
        scale: wiz.browsing ? 1.0 : 0.94
        Behavior on opacity { NumberAnimation { duration: 180 } }
        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "Select replacement for " + wiz.pickingTargetFile
                    color: "#e8f5ee"; font.pixelSize: 15; font.weight: Font.Medium
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
                Text { text: "\u2715"; color: "#8fb3a4"; font.pixelSize: 16; MouseArea { anchors.fill: parent; onClicked: wiz.browsing = false } }
            }

            Text {
                text: wiz.currentDir
                color: "#6f9585"; font.pixelSize: 11
                elide: Text.ElideMiddle
                Layout.fillWidth: true
            }

            Text {
                visible: wiz.currentDir !== "/media"
                text: "\u2191 Up"
                color: "#7fd6b4"; font.pixelSize: 13
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        var parts = wiz.currentDir.split("/")
                        parts.pop()
                        var up = parts.join("/")
                        wiz.refreshDir(up.length > 0 ? up : "/media")
                    }
                }
            }

            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentHeight: browseCol.height
                clip: true
                ColumnLayout {
                    id: browseCol
                    width: parent.width
                    spacing: 6

                    Text {
                        visible: dirModel.items.length === 0
                        text: "Empty, or no storage device mounted here."
                        color: "#6f9585"; font.pixelSize: 13
                        Layout.topMargin: 20
                        Layout.alignment: Qt.AlignHCenter
                    }

                    Repeater {
                        model: dirModel.items
                        delegate: Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 46
                            radius: 10
                            color: rowMouse.containsMouse ? "#1f4a40" : "transparent"
                            readonly property bool selectable: modelData.isDir || modelData.isDb
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 10
                                Text {
                                    text: modelData.isDir ? "\u{1F4C1}" : (modelData.isDb ? "\u{1F5C4}" : "\u{1F4C4}")
                                    font.pixelSize: 15
                                }
                                Text {
                                    text: modelData.name
                                    color: modelData.isDb ? "#7fd6b4" : "#dff2ea"
                                    font.pixelSize: 13
                                    Layout.fillWidth: true
                                    elide: Text.ElideMiddle
                                }
                                Text { text: modelData.sizeLabel; color: "#6f9585"; font.pixelSize: 11 }
                            }
                            MouseArea {
                                id: rowMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: parent.selectable
                                onClicked: {
                                    if (modelData.isDir) {
                                        wiz.refreshDir(modelData.path)
                                    } else if (modelData.isDb) {
                                        var l = wiz.extraDbs.filter(function(d) { return d.targetFile !== wiz.pickingTargetFile })
                                        l.push({
                                            sourcePath: modelData.path,
                                            targetFile: wiz.pickingTargetFile,
                                            name: modelData.name,
                                            sizeLabel: modelData.sizeLabel
                                        })
                                        wiz.extraDbs = l
                                        wiz.browsing = false
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
