import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15

// Full-page scanned mushaf image reader. One edition at a time
// (root.navMushafName), paginated, with pinch/drag zoom, resume-last-page,
// and a copyright notice banner (these are scans of printed mushafs -
// always shown so the reading-only, non-redistribution intent is clear).
Rectangle {
    id: view
    anchors.fill: parent
    color: "#10241f"

    property string mushafName: ""
    property string displayName: ""
    property int currentPage: 1
    property int minPage: 1
    property int maxPage: 1
    property string imagePath: ""

    property var mushafMeta: mushafBackend.mushafList()

    function metaFor(name) {
        for (var i = 0; i < mushafMeta.length; i++) {
            if (mushafMeta[i].mushafName === name) return mushafMeta[i]
        }
        return { displayName: name, minPage: 1, maxPage: 1 }
    }

    function loadPage() {
        // Keep whatever zoom level the reader is at across a page turn -
        // resetting to fit-to-screen every turn was surprising (you'd
        // zoom in to read a line, flip the page, and get thrown back out
        // to full zoom-out). Only the scroll position snaps back to the
        // top-left, since the old pan offset doesn't mean anything on a
        // new page image.
        flick.contentX = 0
        flick.contentY = 0
        var p = mushafBackend.pageImagePath(mushafName, currentPage)
        imagePath = p !== "" ? "file://" + p : ""
    }

    function goToPage(p) {
        if (p < minPage || p > maxPage) return
        currentPage = p
        loadPage()
    }

    function saveCurrentProgress() {
        mushafBackend.saveProgress(mushafName, currentPage)
    }

    Component.onCompleted: {
        mushafName = root.navMushafName
        var meta = metaFor(mushafName)
        displayName = meta.displayName
        minPage = meta.minPage
        maxPage = meta.maxPage

        if (root.navMushafPage > 0) {
            currentPage = root.navMushafPage
        } else {
            var last = mushafBackend.lastProgress()
            currentPage = (last.mushafName === mushafName && last.pageNumber > 0)
                ? last.pageNumber : minPage
        }
        root.navMushafName = ""
        root.navMushafPage = -1
        loadPage()
    }

    Component.onDestruction: saveCurrentProgress()

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 12

        // ---- Top bar ----
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Text {
                text: "\u2190"
                color: "#7fd6b4"
                font.pixelSize: 20
                MouseArea { anchors.fill: parent; onClicked: { view.saveCurrentProgress(); root.goBack() } }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Text {
                    text: view.displayName
                    color: "#e8f5ee"
                    font.pixelSize: 16
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                Text {
                    text: "Page " + view.currentPage + " of " + view.maxPage
                    color: "#8fb3a4"
                    font.pixelSize: 11
                }
            }
            Rectangle {
                width: 36; height: 36; radius: 18
                color: "#173832"
                Text { anchors.centerIn: parent; text: "\u2212"; color: "#7fd6b4"; font.pixelSize: 18 }
                MouseArea { anchors.fill: parent; onClicked: zoomArea.zoomStep(-1) }
            }
            Rectangle {
                width: 36; height: 36; radius: 18
                color: "#173832"
                Text { anchors.centerIn: parent; text: "+"; color: "#7fd6b4"; font.pixelSize: 18 }
                MouseArea { anchors.fill: parent; onClicked: zoomArea.zoomStep(1) }
            }
        }

        // ---- Copyright / provenance notice ----
        Rectangle {
            Layout.fillWidth: true
            height: copyrightText.implicitHeight + 16
            radius: 10
            color: "#173832"
            border.color: "#2f4b43"
            border.width: 1

            Text {
                id: copyrightText
                anchors.fill: parent
                anchors.margins: 8
                text: "\u00A9 " + view.displayName + " \u2014 scanned mushaf pages shown for personal reading only. "
                      + "All rights to the original printed mushaf belong to its respective publisher."
                color: "#8fb3a4"
                font.pixelSize: 10
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
            }
        }

        // ---- Page image, pinch/drag zoomable ----
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 16
            color: "#173832"
            clip: true

            // Ctrl+scroll (and Ctrl + two-finger trackpad scroll, which most
            // desktop environments deliver as a wheel event with the Control
            // modifier rather than a true pinch gesture) zooms the page.
            // acceptedModifiers means plain scrolling is left alone and
            // falls through to the Flickable below for panning.
            WheelHandler {
                id: wheelZoom
                target: null
                acceptedModifiers: Qt.ControlModifier
                onWheel: (event) => {
                    var factor = event.angleDelta.y > 0 ? 1.15 : (1 / 1.15)
                    var oldZoom = zoomArea.zoom
                    var newZoom = zoomArea.clampZoom(oldZoom * factor)
                    if (newZoom === oldZoom) return

                    // Keep the point under the cursor fixed while zooming,
                    // instead of always zooming around the center.
                    var cursorX = flick.contentX + event.x
                    var cursorY = flick.contentY + event.y
                    var ratio = newZoom / oldZoom
                    zoomArea.zoom = newZoom
                    flick.contentX = cursorX * ratio - event.x
                    flick.contentY = cursorY * ratio - event.y
                }
            }

            Flickable {
                id: flick
                anchors.fill: parent
                contentWidth: Math.max(width, pageImage.width * pageImage.scale)
                contentHeight: Math.max(height, pageImage.height * pageImage.scale)
                boundsBehavior: Flickable.StopAtBounds
                clip: true

                Item {
                    id: zoomArea
                    width: Math.max(flick.width, pageImage.width * pageImage.scale)
                    height: Math.max(flick.height, pageImage.height * pageImage.scale)

                    property real zoom: 1.0
                    readonly property real minZoom: 1.0
                    readonly property real maxZoom: 4.0

                    function clampZoom(z) { return Math.max(minZoom, Math.min(maxZoom, z)) }
                    function resetZoom() { zoom = 1.0 }
                    function zoomStep(dir) { zoom = clampZoom(zoom + dir * 0.4) }

                    Image {
                        id: pageImage
                        anchors.centerIn: parent
                        source: view.imagePath
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        width: flick.width
                        height: flick.height
                        scale: zoomArea.zoom
                        cache: false

                        BusyIndicator {
                            anchors.centerIn: parent
                            running: pageImage.status === Image.Loading
                            visible: running
                        }

                        Text {
                            visible: view.imagePath === "" || pageImage.status === Image.Error
                            anchors.centerIn: parent
                            text: "Page image not available"
                            color: "#8fb3a4"
                            font.pixelSize: 13
                        }
                    }

                    PinchArea {
                        anchors.fill: parent
                        // No pinch.target set - zoom is handled manually via
                        // onPinchUpdated below, so it can be clamped to
                        // minZoom/maxZoom instead of the unbounded automatic
                        // transform PinchArea would otherwise apply.
                        onPinchUpdated: {
                            zoomArea.zoom = zoomArea.clampZoom(zoomArea.zoom * (pinch.scale / pinch.previousScale))
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        // Double-tap/click to toggle between fit and 2x zoom -
                        // the simplest reliable zoom gesture on a mouse, in
                        // addition to the pinch gesture above (touch) and the
                        // +/- buttons (any input).
                        onDoubleClicked: zoomArea.zoom = zoomArea.zoom > 1.0 ? 1.0 : 2.0
                    }
                }
            }

            // Left/right screen-edge swipe zones to turn pages without
            // fighting the Flickable's own pan-drag above (only active
            // when not zoomed in, so a zoomed-in pan drag isn't hijacked
            // into a page turn).
            MouseArea {
                visible: zoomArea.zoom <= 1.01
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 48
                onClicked: view.goToPage(view.currentPage - 1)
            }
            MouseArea {
                visible: zoomArea.zoom <= 1.01
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 48
                onClicked: view.goToPage(view.currentPage + 1)
            }
        }

        // ---- Page navigation row ----
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Rectangle {
                Layout.fillWidth: true
                height: 44
                radius: 10
                color: view.currentPage > view.minPage ? "#0f6e56" : "#173832"
                Text { anchors.centerIn: parent; text: "\u2190 Previous"; color: "#fff"; font.pixelSize: 13 }
                MouseArea { anchors.fill: parent; onClicked: view.goToPage(view.currentPage - 1) }
            }

            Rectangle {
                width: 100
                height: 44
                radius: 10
                color: "#173832"
                border.color: "#2f4b43"
                border.width: 1

                TextField {
                    id: pageJumpField
                    anchors.fill: parent
                    anchors.margins: 4
                    horizontalAlignment: Text.AlignHCenter
                    color: "#e8f5ee"
                    placeholderText: "Page"
                    placeholderTextColor: "#5f8a7b"
                    validator: IntValidator { bottom: view.minPage; top: view.maxPage }
                    background: Item {}
                    onAccepted: {
                        var p = parseInt(text)
                        if (!isNaN(p)) view.goToPage(p)
                        text = ""
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 44
                radius: 10
                color: view.currentPage < view.maxPage ? "#0f6e56" : "#173832"
                Text { anchors.centerIn: parent; text: "Next \u2192"; color: "#fff"; font.pixelSize: 13 }
                MouseArea { anchors.fill: parent; onClicked: view.goToPage(view.currentPage + 1) }
            }
        }
    }

    Keys.onLeftPressed: goToPage(currentPage - 1)
    Keys.onRightPressed: goToPage(currentPage + 1)
    focus: true
}
