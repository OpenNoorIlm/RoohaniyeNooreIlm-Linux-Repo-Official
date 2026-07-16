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
        // to full zoom-out). The scroll position re-centers rather than
        // snapping to the top-left corner, since the old pan offset
        // doesn't mean anything on a new page image and landing in a
        // corner every turn was disorienting when zoomed in.
        flick.contentX = Math.max(0, (flick.contentWidth - flick.width) / 2)
        flick.contentY = Math.max(0, (flick.contentHeight - flick.height) / 2)
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

            Flickable {
                id: flick
                anchors.fill: parent
                contentWidth: Math.max(width, pageImage.width * pageImage.scale)
                contentHeight: Math.max(height, pageImage.height * pageImage.scale)
                boundsBehavior: Flickable.StopAtBounds
                clip: true
                // All panning and zooming below is handled manually by
                // interactionArea. Flickable's own drag/wheel handling is
                // switched off so it can never compete with (and silently
                // swallow events from) that handler - that competition was
                // the root cause of zoom-out, drag-panning and shift+scroll
                // all doing nothing once the page was zoomed in.
                interactive: false

                Item {
                    id: zoomArea
                    width: Math.max(flick.width, pageImage.width * pageImage.scale)
                    height: Math.max(flick.height, pageImage.height * pageImage.scale)

                    property real zoom: 1.0
                    readonly property real minZoom: 1.0
                    readonly property real maxZoom: 4.0

                    function clampZoom(z) { return Math.max(minZoom, Math.min(maxZoom, z)) }
                    function resetZoom() { zoom = 1.0 }

                    // Zoom in/out around a fixed viewport point (vx, vy),
                    // e.g. the cursor position or the center of the screen -
                    // shared by wheel-zoom, the +/- buttons and double-click,
                    // so the point under vx/vy stays visually still instead
                    // of the view always re-centering on zoom.
                    function setZoomAt(newZoom, vx, vy) {
                        newZoom = clampZoom(newZoom)
                        if (newZoom === zoom) return
                        var ratio = newZoom / zoom
                        var maxX = Math.max(0, flick.contentWidth * ratio - flick.width)
                        var maxY = Math.max(0, flick.contentHeight * ratio - flick.height)
                        var cursorX = flick.contentX + vx
                        var cursorY = flick.contentY + vy
                        zoom = newZoom
                        flick.contentX = Math.max(0, Math.min(maxX, cursorX * ratio - vx))
                        flick.contentY = Math.max(0, Math.min(maxY, cursorY * ratio - vy))
                    }

                    function zoomStep(dir) { setZoomAt(zoom + dir * 0.4, flick.width / 2, flick.height / 2) }

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
                }
            }

            // Single owner of all pointer/touch/wheel input for the reader,
            // sitting ON TOP of the Flickable as a sibling - deliberately
            // NOT declared inside it. Anything declared inside a Flickable
            // gets auto-reparented into its scrolling contentItem, so a
            // MouseArea in there reports mouse.x/y in a coordinate frame
            // that itself shifts every time we write to contentX/contentY.
            // That was the actual cause of drag-panning (and shift+scroll,
            // and the ctrl+scroll zoom-anchor point) glitching: each event
            // fed back into the coordinates of the next one. Living outside
            // the Flickable, this area's coordinates stay fixed to the
            // viewport, so plain dx/dy math against flick.contentX/Y works.
            //
            // PinchArea wraps the MouseArea to add two-finger pinch-to-zoom;
            // a single touch point passes straight through PinchArea to the
            // MouseArea underneath, so one-finger drag-to-pan and
            // double-tap-to-zoom work on touch the same as with a mouse.
            PinchArea {
                id: pinchZoomArea
                anchors.fill: flick
                pinch.target: null // zoom is driven manually via setZoomAt

                onPinchUpdated: (pinch) => {
                    zoomArea.setZoomAt(zoomArea.zoom * (pinch.scale / pinch.previousScale),
                                        pinch.center.x, pinch.center.y)
                }

                MouseArea {
                    id: interactionArea
                    anchors.fill: parent
                    property real lastX: 0
                    property real lastY: 0

                    onPressed: (mouse) => { lastX = mouse.x; lastY = mouse.y }
                    onPositionChanged: (mouse) => {
                        if (!pressed) return
                        var dx = mouse.x - lastX
                        var dy = mouse.y - lastY
                        lastX = mouse.x
                        lastY = mouse.y
                        var maxX = Math.max(0, flick.contentWidth - flick.width)
                        var maxY = Math.max(0, flick.contentHeight - flick.height)
                        flick.contentX = Math.max(0, Math.min(maxX, flick.contentX - dx))
                        flick.contentY = Math.max(0, Math.min(maxY, flick.contentY - dy))
                    }

                    onDoubleClicked: (mouse) => {
                        zoomArea.setZoomAt(zoomArea.zoom > 1.0 ? 1.0 : 2.0, mouse.x, mouse.y)
                    }

                    onWheel: (wheel) => {
                        if (wheel.modifiers & Qt.ControlModifier) {
                            var factor = wheel.angleDelta.y > 0 ? 1.15 : (1 / 1.15)
                            zoomArea.setZoomAt(zoomArea.zoom * factor, wheel.x, wheel.y)
                        } else if (wheel.modifiers & Qt.ShiftModifier) {
                            var deltaX = wheel.angleDelta.x !== 0 ? wheel.angleDelta.x : wheel.angleDelta.y
                            var maxX = Math.max(0, flick.contentWidth - flick.width)
                            flick.contentX = Math.max(0, Math.min(maxX, flick.contentX - deltaX))
                        } else {
                            var maxY = Math.max(0, flick.contentHeight - flick.height)
                            flick.contentY = Math.max(0, Math.min(maxY, flick.contentY - wheel.angleDelta.y))
                        }
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
        // layoutDirection: RightToLeft so Next lands on the left and
        // Previous on the right - an Arabic mushaf reads right-to-left,
        // so the "forward" direction through the book is leftward on
        // screen. This matches that reading direction instead of the
        // default LTR previous-then-next ordering.
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            layoutDirection: Qt.RightToLeft

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
                    // Reflects the live page number as pages turn (edge
                    // swipe, Left/Right keys, or the buttons here), instead
                    // of only ever showing a typed value and going blank
                    // after every jump. Only synced while not focused, so
                    // it never overwrites what's mid-typing.
                    text: activeFocus ? text : String(view.currentPage)
                    validator: IntValidator { bottom: view.minPage; top: view.maxPage }
                    background: Item {}
                    onAccepted: {
                        var p = parseInt(text)
                        if (!isNaN(p)) view.goToPage(p)
                        focus = false
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
