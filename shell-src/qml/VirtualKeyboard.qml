import QtQuick 2.15
import QtQuick.Layouts 1.15

// ---- Self-built on-screen keyboard (deliberately NOT the Qt
// QtVirtualKeyboard plugin - that module isn't installed on this system
// and would need a system package / rebuild of Qt itself to add, which
// doesn't fit the project's "works out of the box, nothing extra to
// install" philosophy). Works by writing directly into whatever item
// currently has active focus (TextField/TextArea both expose
// insert()/remove()/cursorPosition/text, which is all this needs) -
// so it works with ANY text field in the app for free, with zero
// per-screen wiring. Purely additive: a physical keyboard or mouse
// keeps working exactly as before whether this is open or not, since
// it never grabs focus or intercepts real input events itself. ----
Rectangle {
    id: kb
    color: theme.card
    radius: 0
    border.width: 1
    border.color: theme.dark ? "#22493f" : "#d7e6df"

    // The item to type into. Main.qml keeps this pointed at
    // Window.activeFocusItem so it always follows whatever field the
    // user last tapped, without any screen having to wire it up itself.
    property var target: null
    property bool shiftOn: false
    property bool symbolsOn: false
    property bool capsLock: false

    signal hideRequested()
    signal doneRequested()

    function targetOk() {
        return target !== null && typeof target.insert === "function"
    }
    function insertText(t) {
        if (!targetOk()) return
        target.insert(target.cursorPosition, t)
        if (shiftOn && !capsLock) shiftOn = false
    }
    function backspace() {
        if (!targetOk()) return
        if (target.selectedText && target.selectedText.length > 0) {
            target.remove(target.selectionStart, target.selectionEnd)
        } else if (target.cursorPosition > 0) {
            target.remove(target.cursorPosition - 1, target.cursorPosition)
        }
    }

    readonly property var rowsLetters: [
        ["q","w","e","r","t","y","u","i","o","p"],
        ["a","s","d","f","g","h","j","k","l"],
        ["z","x","c","v","b","n","m"]
    ]
    readonly property var rowsSymbols: [
        ["1","2","3","4","5","6","7","8","9","0"],
        ["@","#","$","_","&","-","+","(",")","/"],
        ["*","\"","'",":",";","!","?"]
    ]

    function keyLabel(k) {
        if (symbolsOn) return k
        return (shiftOn || capsLock) ? k.toUpperCase() : k
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 6

        // Top strip: drag-free, just a hint + hide button.
        RowLayout {
            Layout.fillWidth: true
            Text {
                text: "Keyboard"
                color: theme.subtext
                font.pixelSize: 12
                Layout.fillWidth: true
            }
            Rectangle {
                width: 30; height: 30; radius: 8
                color: "transparent"
                Text { anchors.centerIn: parent; text: "\u25BC"; color: theme.subtext; font.pixelSize: 13 }
                MouseArea { anchors.fill: parent; onClicked: kb.hideRequested() }
            }
        }

        Repeater {
            model: symbolsOn ? rowsSymbols : rowsLetters
            delegate: Row {
                Layout.alignment: Qt.AlignHCenter
                spacing: 5
                // Offset middle/bottom rows slightly, like a real keyboard.
                property real indent: index === 1 ? 14 : (index === 2 ? 30 : 0)
                leftPadding: indent
                Repeater {
                    model: modelData
                    delegate: Rectangle {
                        width: 46; height: 44; radius: 8
                        color: keyArea.pressed ? theme.accent : (theme.dark ? "#0f2b25" : "#f1f6f3")
                        Text {
                            anchors.centerIn: parent
                            text: kb.keyLabel(modelData)
                            color: keyArea.pressed ? "#ffffff" : theme.text
                            font.pixelSize: 17
                        }
                        MouseArea {
                            id: keyArea
                            anchors.fill: parent
                            onClicked: kb.insertText(kb.keyLabel(modelData))
                        }
                    }
                }
            }
        }

        // Bottom action row: shift/123, space, backspace, done.
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 2
            spacing: 6

            Rectangle {
                width: 60; height: 44; radius: 8
                color: (kb.shiftOn || kb.capsLock) ? theme.accent : (theme.dark ? "#0f2b25" : "#f1f6f3")
                visible: !kb.symbolsOn
                Text { anchors.centerIn: parent; text: "\u21E7"; color: (kb.shiftOn || kb.capsLock) ? "#ffffff" : theme.text; font.pixelSize: 18 }
                MouseArea {
                    anchors.fill: parent
                    onClicked: kb.shiftOn = !kb.shiftOn
                    onDoubleClicked: { kb.capsLock = !kb.capsLock; kb.shiftOn = false }
                }
            }
            Rectangle {
                width: 60; height: 44; radius: 8
                color: theme.dark ? "#0f2b25" : "#f1f6f3"
                Text { anchors.centerIn: parent; text: kb.symbolsOn ? "ABC" : "123"; color: theme.text; font.pixelSize: 13 }
                MouseArea { anchors.fill: parent; onClicked: kb.symbolsOn = !kb.symbolsOn }
            }
            Rectangle {
                Layout.fillWidth: true
                height: 44; radius: 8
                color: theme.dark ? "#0f2b25" : "#f1f6f3"
                MouseArea { anchors.fill: parent; onClicked: kb.insertText(" ") }
            }
            Rectangle {
                width: 66; height: 44; radius: 8
                color: theme.dark ? "#0f2b25" : "#f1f6f3"
                Text { anchors.centerIn: parent; text: "\u232B"; color: theme.text; font.pixelSize: 18 }
                MouseArea {
                    anchors.fill: parent
                    onPressed: { kb.backspace(); backspaceRepeat.start() }
                    onReleased: backspaceRepeat.stop()
                    Timer { id: backspaceRepeat; interval: 90; repeat: true; onTriggered: kb.backspace() }
                }
            }
            Rectangle {
                width: 76; height: 44; radius: 8
                color: theme.accent
                Text { anchors.centerIn: parent; text: "Done"; color: "#ffffff"; font.pixelSize: 13; font.weight: Font.Medium }
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        if (kb.targetOk() && typeof target.accepted === "function") { /* no-op, just informational */ }
                        kb.doneRequested()
                    }
                }
            }
        }
    }
}
