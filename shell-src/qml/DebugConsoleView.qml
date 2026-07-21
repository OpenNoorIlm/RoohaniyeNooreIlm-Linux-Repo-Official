import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15

Rectangle {
    anchors.fill: parent
    color: root.theme.bg

    property var history: [] // list of {cmd, output}

    // ---- Disk + folder picker state ----
    property bool pickerOpen: true
    property var diskList: []
    property string currentBrowseDisk: "" // root path of the disk currently being browsed ("" = still choosing a disk)
    property string currentBrowsePath: ""
    property var folderList: []
    // Set from checkFolderAccess()'s "reason" whenever the current folder
    // couldn't be read (e.g. permission denied) - empty string means either
    // the folder is genuinely empty or hasn't been checked yet.
    property string folderAccessDenied: ""
    // Single-tap on a folder row selects it (highlighted, doesn't navigate);
    // double-tap enters it. Reset whenever the folder list itself changes.
    property string selectedSubfolder: ""
    // Set when confirmFolder() rejects a pick because the folder isn't
    // actually writable (e.g. another user's home dir) - shown as an
    // inline error so the picker stays open instead of silently closing
    // and falling back to some other location with no explanation.
    property string saveError: ""

    function refreshFolderList() {
        var res = debugBackend.checkFolderAccess(currentBrowsePath)
        if (res.ok) {
            folderList = res.folders
            folderAccessDenied = ""
        } else {
            folderList = []
            folderAccessDenied = res.reason
        }
    }

    function openPicker() {
        currentBrowseDisk = ""
        currentBrowsePath = ""
        selectedSubfolder = ""
        folderAccessDenied = ""
        saveError = ""
        diskList = debugBackend.listLogTargetDisks()
        pickerOpen = true
    }

    function chooseDisk(path) {
        currentBrowseDisk = path
        currentBrowsePath = path
        selectedSubfolder = ""
        saveError = ""
        refreshFolderList()
    }

    function goUp() {
        selectedSubfolder = ""
        saveError = ""
        if (currentBrowsePath === currentBrowseDisk) {
            // back out to the disk list entirely
            currentBrowseDisk = ""
            currentBrowsePath = ""
            return
        }
        var idx = currentBrowsePath.lastIndexOf("/")
        currentBrowsePath = idx > 0 ? currentBrowsePath.substring(0, idx) : "/"
        refreshFolderList()
    }

    function goInto(path) {
        selectedSubfolder = ""
        saveError = ""
        currentBrowsePath = path
        refreshFolderList()
    }

    function confirmFolder() {
        // If a subfolder is single-tap-selected (but not entered), save
        // there. Otherwise save in the folder currently being browsed.
        var target = selectedSubfolder !== "" ? selectedSubfolder : currentBrowsePath
        var res = debugBackend.trySelectLogDirectory(target)
        if (res.ok) {
            saveError = ""
            pickerOpen = false
        } else {
            // Keep the picker open and show exactly why this folder was
            // rejected, instead of silently closing and letting
            // ensureLogFile() fall back to some other location later with
            // no explanation.
            saveError = res.reason
        }
    }

    function createNewFolder(name) {
        var p = debugBackend.createFolder(currentBrowsePath, name)
        if (p !== "") {
            currentBrowsePath = p
            selectedSubfolder = ""
            refreshFolderList()
        }
    }

    Component.onCompleted: openPicker()

    function pushEntry(cmd, output) {
        var h = history.slice()
        h.push({ cmd: cmd, output: output })
        history = h
        outputList.positionViewAtEnd()
    }

    function runAndShow(cmd) {
        if (cmd === "") return
        var out = debugBackend.runCommand(cmd)
        pushEntry(cmd, out)
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 40
        spacing: 16

        // ---- Header ----
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            Image {
                source: "qrc:/assets/images/debug_icon.png"
                Layout.preferredWidth: 40
                Layout.preferredHeight: 40
                fillMode: Image.PreserveAspectFit
                smooth: true
            }
            ColumnLayout {
                spacing: 2
                Text { text: "Debug Console"; color: root.theme.text; font.pixelSize: 24; font.weight: Font.Medium }
                Text {
                    text: debugBackend.logFilePath !== ""
                        ? ("Saving to: " + debugBackend.logFilePath)
                        : (debugBackend.selectedLogDir() !== ""
                            ? ("Will save under: " + debugBackend.selectedLogDir())
                            : "No log location chosen yet")
                    color: root.theme.subtext
                    font.pixelSize: 12
                    elide: Text.ElideMiddle
                    Layout.maximumWidth: 700
                }
                Text {
                    text: debugBackend.commandListSource() !== ""
                        ? ("Commands from: " + debugBackend.commandListSource())
                        : "commands.txt not found yet (checked USB root + built-in) - tap \"Run all commands\" to check again"
                    color: root.theme.subtext
                    font.pixelSize: 11
                    elide: Text.ElideMiddle
                    Layout.maximumWidth: 700
                }
            }
            Item { Layout.fillWidth: true }
            Rectangle {
                width: changeLocLabel.implicitWidth + 24
                height: 34
                radius: 8
                color: changeLocMouse.pressed ? root.theme.accent : root.theme.card
                border.width: 1
                border.color: root.theme.dark ? "#22493f" : "#d7e6df"
                Text {
                    id: changeLocLabel
                    anchors.centerIn: parent
                    text: "Change log location"
                    color: root.theme.text
                    font.pixelSize: 12
                }
                MouseArea {
                    id: changeLocMouse
                    anchors.fill: parent
                    onClicked: {
                        root.sounds.buttonClick()
                        openPicker()
                    }
                }
            }
        }

        // ---- Quick action buttons ----
        Flow {
            Layout.fillWidth: true
            spacing: 10

            Repeater {
                model: [
                    { label: "Run full diagnostics", cmd: "__DIAG__" },
                    { label: "\u25B6 Run all commands (commands.txt)", cmd: "__RUNALL__" },
                    { label: "nmcli device status", cmd: "nmcli device status" },
                    { label: "nmcli wifi list", cmd: "nmcli device wifi list" },
                    { label: "lsmod | grep rtl", cmd: "lsmod | grep -i rtl" },
                    { label: "rfkill list", cmd: "rfkill list" },
                    { label: "dmesg tail", cmd: "dmesg | tail -40" }
                ]
                delegate: Rectangle {
                    width: quickLabel.implicitWidth + 28
                    height: 40
                    radius: 10
                    color: quickMouse.pressed ? root.theme.accent : (modelData.cmd === "__RUNALL__" ? root.theme.cardAlt : root.theme.card)
                    border.width: 1
                    border.color: root.theme.dark ? "#22493f" : "#d7e6df"
                    Text {
                        id: quickLabel
                        anchors.centerIn: parent
                        text: modelData.label
                        color: modelData.cmd === "__RUNALL__" ? "#ffffff" : root.theme.text
                        font.pixelSize: 13
                        font.weight: modelData.cmd === "__RUNALL__" ? Font.Medium : Font.Normal
                    }
                    MouseArea {
                        id: quickMouse
                        anchors.fill: parent
                        onClicked: {
                            root.sounds.buttonClick()
                            if (modelData.cmd === "__DIAG__") {
                                var out = debugBackend.runDiagnostics()
                                pushEntry("(full diagnostics)", out)
                            } else if (modelData.cmd === "__RUNALL__") {
                                var results = debugBackend.runAllFromFile()
                                if (results.length === 0) {
                                    pushEntry("(run all commands)", "No commands.txt found - place one at the root of a USB/SD device, or check the built-in copy at /opt/roohaniye/data/commands.txt")
                                } else {
                                    var h = history.slice()
                                    for (var i = 0; i < results.length; i++) {
                                        h.push({ cmd: results[i].label + "  [" + results[i].cmd + "]", output: results[i].output })
                                    }
                                    history = h
                                    outputList.positionViewAtEnd()
                                }
                            } else {
                                runAndShow(modelData.cmd)
                            }
                        }
                    }
                }
            }
        }

        // ---- Scrollable command/output history ----
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 16
            color: root.theme.card
            border.width: 1
            border.color: root.theme.dark ? "#22493f" : "#d7e6df"

            ListView {
                id: outputList
                anchors.fill: parent
                anchors.margins: 16
                clip: true
                spacing: 14
                model: history

                delegate: ColumnLayout {
                    width: outputList.width
                    spacing: 4
                    Text {
                        text: "$ " + modelData.cmd
                        color: root.theme.accent
                        font.family: "monospace"
                        font.pixelSize: 14
                        font.weight: Font.Medium
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }
                    Text {
                        text: modelData.output === "" ? "(no output)" : modelData.output
                        color: root.theme.text
                        font.family: "monospace"
                        font.pixelSize: 12
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }
                }

                Text {
                    visible: history.length === 0
                    anchors.centerIn: parent
                    text: "Run a command below, or tap a quick action above."
                    color: root.theme.subtext
                    font.pixelSize: 13
                }
            }
        }

        // ---- Command input row ----
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 52
                radius: 12
                color: root.theme.card
                border.width: 1
                border.color: cmdInput.activeFocus ? root.theme.accent : (root.theme.dark ? "#22493f" : "#d7e6df")

                TextInput {
                    id: cmdInput
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    verticalAlignment: TextInput.AlignVCenter
                    color: root.theme.text
                    font.family: "monospace"
                    font.pixelSize: 14
                    clip: true
                    onAccepted: {
                        runAndShow(text)
                        text = ""
                    }
                }

                Text {
                    visible: cmdInput.text === "" && !cmdInput.activeFocus
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Type a command..."
                    color: root.theme.subtext
                    font.pixelSize: 14
                }
            }

            Rectangle {
                width: 90
                height: 52
                radius: 12
                color: root.theme.cardAlt
                Text { anchors.centerIn: parent; text: "Run"; color: "#ffffff"; font.pixelSize: 14; font.weight: Font.Medium }
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        root.sounds.buttonClick()
                        runAndShow(cmdInput.text)
                        cmdInput.text = ""
                    }
                }
            }
        }
    }

    // ---- Disk + folder picker overlay ----
    // Shown on first load and whenever "Change log location" is tapped.
    // Step 1: pick a disk (currentBrowseDisk === ""). Step 2: browse
    // folders on that disk and confirm one.
    Rectangle {
        anchors.fill: parent
        color: root.theme.bg
        visible: pickerOpen
        z: 2100 // above navCluster (z:2000) so our buttons aren't hidden underneath it

        ColumnLayout {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.leftMargin: 40
            anchors.rightMargin: 40
            anchors.topMargin: 40
            // navCluster (back/home/menu/orientation) floats bottom-left at
            // 22px margin + 56px tall = 78px footprint - clear it with room
            // to spare so our own action row never renders underneath it.
            anchors.bottomMargin: 110
            spacing: 16

            Text {
                text: currentBrowseDisk === "" ? "Where should logs be saved?" : "Choose a folder"
                color: root.theme.text
                font.pixelSize: 22
                font.weight: Font.Medium
            }

            Text {
                visible: currentBrowseDisk !== ""
                text: currentBrowsePath
                color: root.theme.subtext
                font.pixelSize: 12
                elide: Text.ElideMiddle
                Layout.maximumWidth: 900
            }

            // ---- Step 1: disk list ----
            Rectangle {
                visible: currentBrowseDisk === ""
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 16
                color: root.theme.card
                border.width: 1
                border.color: root.theme.dark ? "#22493f" : "#d7e6df"

                ListView {
                    anchors.fill: parent
                    anchors.margins: 12
                    clip: true
                    spacing: 8
                    model: diskList

                    delegate: Rectangle {
                        width: parent ? parent.width : 0
                        height: 56
                        radius: 10
                        color: diskMouse.pressed ? root.theme.accent : root.theme.cardAlt
                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.label + "   (" + modelData.path + ")"
                            color: "#ffffff"
                            font.pixelSize: 14
                            elide: Text.ElideMiddle
                            width: parent.width - 32
                        }
                        MouseArea {
                            id: diskMouse
                            anchors.fill: parent
                            onClicked: {
                                root.sounds.buttonClick()
                                chooseDisk(modelData.path)
                            }
                        }
                    }

                    Text {
                        visible: diskList.length === 0
                        anchors.centerIn: parent
                        text: "No disks found. Plug in a USB/SD device, then reopen this."
                        color: root.theme.subtext
                        font.pixelSize: 13
                    }
                }
            }

            // ---- Step 2: folder browser ----
            Rectangle {
                visible: currentBrowseDisk !== ""
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 16
                color: root.theme.card
                border.width: 1
                border.color: root.theme.dark ? "#22493f" : "#d7e6df"

                ListView {
                    anchors.fill: parent
                    anchors.margins: 12
                    clip: true
                    spacing: 8
                    model: folderList

                    delegate: Rectangle {
                        width: parent ? parent.width : 0
                        height: 48
                        radius: 10
                        color: selectedSubfolder === modelData.path
                            ? root.theme.accent
                            : (folderMouse.pressed ? root.theme.accent : root.theme.cardAlt)
                        border.width: selectedSubfolder === modelData.path ? 2 : 0
                        border.color: "#ffffff"
                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            text: "\uD83D\uDCC1 " + modelData.name + (selectedSubfolder === modelData.path ? "  (selected - tap Save, or double-tap to open)" : "")
                            color: "#ffffff"
                            font.pixelSize: 14
                        }
                        MouseArea {
                            id: folderMouse
                            anchors.fill: parent
                            onClicked: {
                                root.sounds.buttonClick()
                                // single tap: select (toggle), don't navigate
                                selectedSubfolder = (selectedSubfolder === modelData.path) ? "" : modelData.path
                            }
                            onDoubleClicked: {
                                root.sounds.buttonClick()
                                goInto(modelData.path)
                            }
                        }
                    }

                    Text {
                        visible: folderList.length === 0
                        anchors.centerIn: parent
                        anchors.margins: 20
                        width: parent.width - 40
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        text: folderAccessDenied !== "" ? folderAccessDenied : "(no subfolders here)"
                        color: folderAccessDenied !== "" ? "#e0654f" : root.theme.subtext
                        font.pixelSize: 13
                    }
                }
            }

            // ---- Save error banner ----
            // Shown when trySelectLogDirectory() rejected the last pick
            // (e.g. a folder roohaniye can't write into). The picker stays
            // open so the user can choose somewhere else instead of the
            // app silently saving somewhere unexpected.
            Text {
                visible: saveError !== ""
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: "\u26A0 " + saveError
                color: "#e0654f"
                font.pixelSize: 13
            }

            // ---- Action row ----
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Rectangle {
                    visible: currentBrowseDisk !== ""
                    width: upLabel.implicitWidth + 24
                    height: 44
                    radius: 10
                    color: upMouse.pressed ? root.theme.accent : root.theme.cardAlt
                    Text { id: upLabel; anchors.centerIn: parent; text: "\u2190 Up"; color: "#ffffff"; font.pixelSize: 13 }
                    MouseArea { id: upMouse; anchors.fill: parent; onClicked: { root.sounds.buttonClick(); goUp() } }
                }

                Rectangle {
                    visible: currentBrowseDisk !== ""
                    width: newFolderLabel.implicitWidth + 24
                    height: 44
                    radius: 10
                    color: newFolderMouse.pressed ? root.theme.accent : root.theme.cardAlt
                    Text { id: newFolderLabel; anchors.centerIn: parent; text: "+ New folder"; color: "#ffffff"; font.pixelSize: 13 }
                    MouseArea {
                        id: newFolderMouse
                        anchors.fill: parent
                        onClicked: {
                            root.sounds.buttonClick()
                            newFolderPrompt.visible = true
                            newFolderInput.text = ""
                            newFolderInput.forceActiveFocus()
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    visible: currentBrowseDisk !== ""
                    width: saveHereLabel.implicitWidth + 28
                    height: 44
                    radius: 10
                    color: saveHereMouse.pressed ? root.theme.accent : "#2f9e6e"
                    Text {
                        id: saveHereLabel
                        anchors.centerIn: parent
                        text: selectedSubfolder !== "" ? "Use selected folder" : "Save logs here"
                        color: "#ffffff"
                        font.pixelSize: 14
                        font.weight: Font.Medium
                    }
                    MouseArea { id: saveHereMouse; anchors.fill: parent; onClicked: { root.sounds.buttonClick(); confirmFolder() } }
                }
            }

            // ---- New folder inline prompt ----
            RowLayout {
                id: newFolderPrompt
                visible: false
                Layout.fillWidth: true
                spacing: 10

                Rectangle {
                    Layout.fillWidth: true
                    height: 44
                    radius: 10
                    color: root.theme.cardAlt
                    border.width: 1
                    border.color: newFolderInput.activeFocus ? root.theme.accent : "transparent"
                    TextInput {
                        id: newFolderInput
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        verticalAlignment: TextInput.AlignVCenter
                        color: root.theme.text
                        font.pixelSize: 14
                        clip: true
                        onAccepted: {
                            createNewFolder(text)
                            newFolderPrompt.visible = false
                        }
                    }
                }
                Rectangle {
                    width: 70
                    height: 44
                    radius: 10
                    color: root.theme.cardAlt
                    Text { anchors.centerIn: parent; text: "Create"; color: "#ffffff"; font.pixelSize: 13 }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            root.sounds.buttonClick()
                            createNewFolder(newFolderInput.text)
                            newFolderPrompt.visible = false
                        }
                    }
                }
            }
        }
    }
}
