import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15

// Full-screen lock/login overlay. Lives directly in Main.qml (not routed
// through the view Loader) so it can sit above absolutely everything -
// including mid-navigation - the instant authBackend.locked becomes
// true, with no dependency on which screen happens to be loaded.
//
// Two modes, driven entirely by authBackend state:
//  - "login": authBackend.loggedInUser is empty - nobody has signed in
//    this session yet (fresh boot with accounts present, or after an
//    explicit Logout). Shows username + password.
//  - "unlock": a user IS logged in but the session auto-locked from
//    inactivity, or Lock Now was tapped. Shows just the password field
//    for that same user (faster re-entry) plus a small "Not you?" link
//    back to full login mode.
//
// Deliberately a full password re-entry rather than a separate PIN
// system for the quick-unlock case - AuthBackend only stores one
// PBKDF2 hash per user, and adding a second, weaker PIN-based unlock
// path would undercut the "very securely" ask. Touch-friendly sizing
// (large fields/buttons) is the compromise instead.
Rectangle {
    id: lockRoot
    anchors.fill: parent
    color: root.theme.bg

    property bool loginMode: authBackend.loggedInUser === ""
    property string errorText: ""
    property string username: ""
    property bool recoveryMode: false
    property string recoveryStage: "code" // "code" -> "newpass" -> "done"
    property string recoveryShownCode: ""

    // Reset fields whenever the overlay becomes visible again (e.g. a
    // failed attempt shouldn't linger into the next lock).
    onVisibleChanged: {
        if (visible) {
            errorText = ""
            userField.text = ""
            passField.text = ""
            recoveryMode = false
            recoveryStage = "code"
            recoveryShownCode = ""
            passField.forceActiveFocus()
        }
    }

    Image {
        anchors.fill: parent
        visible: root.theme.hasBackground
        source: themeBackend.backgroundImage
        fillMode: Image.PreserveAspectCrop
        opacity: themeBackend.backgroundOpacity * 0.5
        asynchronous: true
        cache: false
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(380, parent.width - 48)
        height: card.implicitHeight + 56
        radius: 24
        color: root.theme.card
        border.width: 1
        border.color: Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.25)

        ColumnLayout {
            id: card
            anchors.fill: parent
            anchors.margins: 28
            spacing: 16

            Image {
                Layout.alignment: Qt.AlignHCenter
                source: "qrc:/assets/images/brand_icon.png"
                Layout.preferredWidth: 56
                Layout.preferredHeight: 56
                fillMode: Image.PreserveAspectFit
                smooth: true
            }

            // ---- Unlock mode: avatar + username, no typing needed for that part ----
            ColumnLayout {
                visible: !lockRoot.loginMode
                Layout.alignment: Qt.AlignHCenter
                spacing: 6
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    width: 56; height: 56; radius: 28
                    color: root.theme.accent
                    Text {
                        anchors.centerIn: parent
                        text: authBackend.loggedInUser.length > 0 ? authBackend.loggedInUser.charAt(0).toUpperCase() : "?"
                        color: "#10241f"
                        font.pixelSize: 22
                        font.weight: Font.Bold
                    }
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: authBackend.loggedInUser
                    color: root.theme.text
                    font.pixelSize: 16
                    font.weight: Font.Medium
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Session locked"
                    color: root.theme.subtext
                    font.pixelSize: 12
                }
            }

            // ---- Login mode header ----
            Text {
                visible: lockRoot.loginMode
                Layout.alignment: Qt.AlignHCenter
                text: "Sign in"
                color: root.theme.text
                font.pixelSize: 18
                font.weight: Font.Medium
            }

            TextField {
                id: userField
                visible: lockRoot.loginMode
                Layout.fillWidth: true
                Layout.preferredHeight: 48
                placeholderText: "Username"
                font.pixelSize: 15
                onAccepted: passField.forceActiveFocus()
            }

            TextField {
                id: passField
                visible: !lockRoot.recoveryMode
                Layout.fillWidth: true
                Layout.preferredHeight: 48
                placeholderText: "Password"
                echoMode: TextInput.Password
                font.pixelSize: 15
                onAccepted: submitBtn.clicked()
            }

            // ---- Forgot-password recovery flow. Two steps: enter the
            // one-time recovery code shown at account-creation time,
            // then set a new password. Using the code invalidates it
            // (single-use) and issues a fresh one, shown once more so
            // the person can write it down again. ----
            ColumnLayout {
                visible: lockRoot.recoveryMode
                Layout.fillWidth: true
                spacing: 10

                Text {
                    Layout.fillWidth: true
                    visible: lockRoot.recoveryStage === "code"
                    text: "Enter the recovery code you saved when this account was created."
                    color: root.theme.subtext
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                }
                TextField {
                    id: recoveryCodeField
                    visible: lockRoot.recoveryStage === "code"
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48
                    placeholderText: "Recovery code (XXXX-XXXX-XXXX)"
                    font.pixelSize: 15
                }
                TextField {
                    id: newPassField
                    visible: lockRoot.recoveryStage === "newpass"
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48
                    placeholderText: "New password"
                    echoMode: TextInput.Password
                    font.pixelSize: 15
                }
                ColumnLayout {
                    visible: lockRoot.recoveryStage === "done"
                    Layout.fillWidth: true
                    spacing: 6
                    Text {
                        Layout.fillWidth: true
                        text: "Password reset. Here's your NEW recovery code — write it down, it won't be shown again:"
                        color: root.theme.subtext
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                    }
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: lockRoot.recoveryShownCode
                        color: root.theme.accent
                        font.pixelSize: 17
                        font.weight: Font.Bold
                        font.family: "monospace"
                    }
                }
            }

            Text {
                visible: lockRoot.errorText !== ""
                Layout.fillWidth: true
                text: lockRoot.errorText
                color: "#e8917f"
                font.pixelSize: 12
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
            }

            Rectangle {
                id: submitBtn
                Layout.fillWidth: true
                Layout.preferredHeight: 48
                radius: 14
                color: root.theme.cardAlt
                Text {
                    anchors.centerIn: parent
                    text: {
                        if (!lockRoot.recoveryMode) return lockRoot.loginMode ? "Log In" : "Unlock"
                        if (lockRoot.recoveryStage === "code") return "Continue"
                        if (lockRoot.recoveryStage === "newpass") return "Reset Password"
                        return "Back to Login"
                    }
                    color: "#ffffff"
                    font.pixelSize: 15
                    font.weight: Font.Medium
                }
                function clicked() {
                    if (lockRoot.recoveryMode) {
                        if (lockRoot.recoveryStage === "code") {
                            if (recoveryCodeField.text.trim() === "") {
                                lockRoot.errorText = "Enter your recovery code."
                                return
                            }
                            lockRoot.errorText = ""
                            lockRoot.recoveryStage = "newpass"
                        } else if (lockRoot.recoveryStage === "newpass") {
                            var uname = lockRoot.loginMode ? userField.text : authBackend.loggedInUser
                            var rr = authBackend.recoverPassword(uname, recoveryCodeField.text, newPassField.text)
                            if (!rr.ok) {
                                lockRoot.errorText = rr.error
                                // Wrong/used code - back to the code step, not password step.
                                lockRoot.recoveryStage = "code"
                                return
                            }
                            lockRoot.errorText = ""
                            lockRoot.recoveryShownCode = rr.recoveryCode
                            lockRoot.recoveryStage = "done"
                        } else {
                            lockRoot.recoveryMode = false
                            lockRoot.recoveryStage = "code"
                            passField.text = ""
                            passField.forceActiveFocus()
                        }
                        return
                    }
                    if (lockRoot.loginMode) {
                        var res = authBackend.login(userField.text, passField.text)
                        if (!res.ok) {
                            lockRoot.errorText = res.error
                            passField.text = ""
                        }
                    } else {
                        var res2 = authBackend.unlock(passField.text)
                        if (!res2.ok) {
                            lockRoot.errorText = res2.error
                            passField.text = ""
                        }
                    }
                }
                MouseArea { anchors.fill: parent; onClicked: submitBtn.clicked() }
            }

            Text {
                visible: !lockRoot.recoveryMode
                Layout.alignment: Qt.AlignHCenter
                text: "Forgot password?"
                color: root.theme.subtext
                font.pixelSize: 12
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -8
                    onClicked: {
                        if (lockRoot.loginMode && userField.text.trim() === "") {
                            lockRoot.errorText = "Enter your username first."
                            return
                        }
                        lockRoot.errorText = ""
                        lockRoot.recoveryMode = true
                        lockRoot.recoveryStage = "code"
                    }
                }
            }

            Text {
                visible: lockRoot.recoveryMode
                Layout.alignment: Qt.AlignHCenter
                text: "Cancel"
                color: root.theme.subtext
                font.pixelSize: 12
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -8
                    onClicked: {
                        lockRoot.recoveryMode = false
                        lockRoot.recoveryStage = "code"
                        lockRoot.errorText = ""
                    }
                }
            }

            Text {
                visible: !lockRoot.loginMode && !lockRoot.recoveryMode
                Layout.alignment: Qt.AlignHCenter
                text: "Not you? Log out"
                color: root.theme.subtext
                font.pixelSize: 12
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -8
                    onClicked: authBackend.logout()
                }
            }
        }
    }
}
