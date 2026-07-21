import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15

// Reminders: simple recurring reminders ("Read Quran" at 8pm daily, etc).
// Backed by reminderBackend (reminderbackend.h/.cpp) - a QSettings-
// persisted JSON list + a 30s poll timer that emits reminderDue(id,title)
// once per matching minute per day. Main.qml listens for that signal
// globally (so a reminder fires no matter which screen is open) and
// shows a full-screen banner + plays sounds.ringtone() - see Main.qml.
Rectangle {
    id: view
    anchors.fill: parent
    color: "#10241f"

    property var editingId: -1 // -1 = add mode, else editing an existing reminder
    property string editTitle: ""
    property int editHour: 20
    property int editMinute: 0
    property var editDays: [] // empty = every day
    property alias reminderModel: reminderModel

    readonly property var dayLabels: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    function openAdd(prefillTitle) {
        editingId = -1
        editTitle = prefillTitle || ""
        editHour = 20
        editMinute = 0
        editDays = []
        editDialog.open()
    }
    function openEdit(r) {
        editingId = r.id
        editTitle = r.title
        editHour = r.hour
        editMinute = r.minute
        editDays = r.days ? r.days.slice() : []
        editDialog.open()
    }
    function toggleEditDay(d) {
        var arr = editDays.slice()
        var idx = arr.indexOf(d)
        if (idx === -1) arr.push(d)
        else arr.splice(idx, 1)
        editDays = arr
    }
    function saveEdit() {
        if (editTitle.trim().length === 0) return
        if (editingId === -1) {
            reminderBackend.addReminder(editTitle.trim(), editHour, editMinute, editDays)
        } else {
            reminderBackend.updateReminder(editingId, editTitle.trim(), editHour, editMinute, editDays)
        }
        editDialog.close()
        reminderModel.refresh()
    }
    function daysSummary(days) {
        if (!days || days.length === 0) return "Every day"
        if (days.length === 7) return "Every day"
        var parts = []
        for (var i = 0; i < days.length; i++) parts.push(dayLabels[days[i]])
        return parts.join(", ")
    }
    function pad2(n) { return (n < 10 ? "0" : "") + n }

    // Simple wrapper so the ListView has something to refresh() against -
    // reminderBackend.reminders() is a plain invokable, not a live model,
    // so we re-pull it into a property on any mutation (add/edit/remove/
    // toggle) rather than binding a ListView.model directly to a function
    // call, which wouldn't be reactive.
    QtObject {
        id: reminderModel
        property var items: reminderBackend.reminders()
        function refresh() { items = reminderBackend.reminders() }
    }

    Component.onCompleted: reminderModel.refresh()

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
                MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: { root.sounds.buttonClick(); root.goBack() } }
            }
            Text { text: "Reminders"; color: "#e8f5ee"; font.pixelSize: 20; font.weight: Font.Medium; Layout.leftMargin: 12; Layout.fillWidth: true }
            Rectangle {
                width: 44; height: 44; radius: 22
                color: "#0f6e56"
                Text { anchors.centerIn: parent; text: "+"; color: "#fff"; font.pixelSize: 22 }
                MouseArea { anchors.fill: parent; onClicked: { root.sounds.buttonClick(); view.openAdd("") } }
            }
        }

        // ---- Quick-add suggestions ----
        Flow {
            Layout.fillWidth: true
            spacing: 8
            Repeater {
                model: reminderBackend.suggestedTitles()
                delegate: Rectangle {
                    height: 30
                    width: sugText.implicitWidth + 20
                    radius: 15
                    color: "#173832"
                    Text { id: sugText; anchors.centerIn: parent; text: modelData; color: "#9fc7b7"; font.pixelSize: 12 }
                    MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: { root.sounds.buttonClick(); view.openAdd(modelData) } }
                }
            }
        }

        Text {
            visible: reminderModel.items.length === 0
            text: "No reminders yet. Tap + or one of the suggestions above to add one."
            color: "#6f9585"
            font.pixelSize: 12
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 10
            model: reminderModel.items

            delegate: Rectangle {
                width: ListView.view.width
                height: 76
                radius: 14
                color: "#173832"
                opacity: modelData.enabled ? 1.0 : 0.5
                Behavior on opacity { NumberAnimation { duration: 150 } }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 10

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3
                        Text { text: modelData.title; color: "#dff2ea"; font.pixelSize: 15; font.weight: Font.Medium }
                        Text {
                            text: view.pad2(modelData.hour) + ":" + view.pad2(modelData.minute) + " \u00b7 " + view.daysSummary(modelData.days)
                            color: "#8fb3a4"
                            font.pixelSize: 12
                        }
                    }

                    Switch {
                        checked: modelData.enabled
                        onToggled: { reminderBackend.setEnabled(modelData.id, checked); reminderModel.refresh() }
                    }

                    Text {
                        text: "\u270E"
                        color: "#7fd6b4"
                        font.pixelSize: 16
                        MouseArea { anchors.fill: parent; anchors.margins: -8; onClicked: { root.sounds.buttonClick(); view.openEdit(modelData) } }
                    }

                    Text {
                        text: "\u2715"
                        color: "#c96a5a"
                        font.pixelSize: 16
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -8
                            onClicked: { root.sounds.buttonClick(); reminderBackend.removeReminder(modelData.id); reminderModel.refresh() }
                        }
                    }
                }
            }
        }
    }

    // ---- Add / edit dialog ----
    Dialog {
        id: editDialog
        anchors.centerIn: parent
        modal: true
        width: 340
        title: view.editingId === -1 ? "New reminder" : "Edit reminder"

        contentItem: ColumnLayout {
            width: 300
            spacing: 14

            TextField {
                Layout.fillWidth: true
                placeholderText: "Title (e.g. Read Quran)"
                text: view.editTitle
                onTextChanged: view.editTitle = text
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Text { text: "Time"; color: "#dff2ea"; font.pixelSize: 13 }
                Item { Layout.fillWidth: true }
                SpinBox {
                    from: 0; to: 23; value: view.editHour
                    onValueModified: view.editHour = value
                    textFromValue: function(v) { return view.pad2(v) }
                }
                Text { text: ":"; color: "#dff2ea"; font.pixelSize: 16 }
                SpinBox {
                    from: 0; to: 59; stepSize: 5; value: view.editMinute
                    onValueModified: view.editMinute = value
                    textFromValue: function(v) { return view.pad2(v) }
                }
            }

            Text { text: "Repeat on"; color: "#dff2ea"; font.pixelSize: 13 }
            Flow {
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: view.dayLabels
                    delegate: Rectangle {
                        width: 44; height: 44; radius: 10
                        color: view.editDays.indexOf(index) !== -1 ? "#0f6e56" : "#173832"
                        Text { anchors.centerIn: parent; text: modelData; color: "#dff2ea"; font.pixelSize: 11 }
                        MouseArea { anchors.fill: parent; onClicked: { root.sounds.buttonClick(); view.toggleEditDay(index) } }
                    }
                }
            }
            Text { text: "No days selected = fires every day."; color: "#6f9585"; font.pixelSize: 10 }
        }

        footer: DialogButtonBox {
            Button { text: "Cancel"; DialogButtonBox.buttonRole: DialogButtonBox.RejectRole }
            Button { text: "Save"; DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole }
        }

        onAccepted: view.saveEdit()
    }
}
