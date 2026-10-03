import QtQuick
import qs.Commons

Rectangle {
    id: root
    property string state: "unknown"
    property string pauseReason: ""
    property color foreground
    property color accent
    property color dim
    property color urgent
    property string fontFamily
    property bool busy: false
    property bool actionEnabled: false
    property bool demo: false
    signal actionRequested
    readonly property bool expired: state === "relink-required" || state === "unlinked"
    readonly property string label: expired ? (state === "unlinked" ? "Not linked" : "Link expired") : state === "closed" ? "Closed · sync paused" : state === "offline" ? "Offline · local archive" : root.pauseReason !== "" ? "Sync paused · " + root.pauseReason : state === "connected" ? "Linked · connected" : state === "connecting" ? "Connecting…" : state === "stopped" ? "Sync stopped" : "Checking link…"
    readonly property string detail: expired ? "Link again to receive new messages." : state === "closed" ? "Open to receive new messages." : root.pauseReason !== "" ? "Sync resumes when this finishes." : state === "connected" ? "Your messages are syncing." : state === "connecting" ? "Waiting for WhatsApp to connect." : state === "offline" ? "Your saved chats are available." : state === "stopped" ? "New messages are not arriving." : "Reading this account’s status."
    readonly property string action: expired ? "Link again" : state === "closed" ? "Open" : state === "offline" ? "Go online" : state === "stopped" && root.pauseReason === "" ? "Resume" : ""
    width: parent.width
    height: Style.space(66)
    radius: Style.cornerRadius
    color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.06)
    border.width: 1
    border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18)
    Rectangle {
        x: Style.space(12)
        y: Style.space(18)
        width: Style.space(6)
        height: width
        radius: width / 2
        color: root.expired ? root.urgent : root.state === "connected" ? root.accent : root.dim
    }
    Column {
        anchors.left: parent.left
        anchors.leftMargin: Style.space(26)
        anchors.right: statusAction.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(4)
        Text {
            textFormat: Text.PlainText
            width: parent.width
            text: root.label
            elide: Text.ElideRight
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
        }
        Text {
            textFormat: Text.PlainText
            width: parent.width
            text: root.detail
            elide: Text.ElideRight
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
        }
    }
    Rectangle {
        id: statusAction
        activeFocusOnTab: visible && actionMouse.enabled
        Accessible.role: Accessible.Button
        Accessible.name: root.action
        Accessible.onPressAction: if (actionMouse.enabled)
            root.actionRequested()
        Keys.onReturnPressed: if (actionMouse.enabled)
            root.actionRequested()
        Keys.onSpacePressed: if (actionMouse.enabled)
            root.actionRequested()
        objectName: "railLinkAction"
        anchors.right: parent.right
        anchors.rightMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        width: visible ? actionText.implicitWidth + Style.space(18) : 0
        height: Style.space(30)
        visible: root.action !== ""
        radius: Style.cornerRadius
        color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, actionMouse.containsMouse ? 0.22 : 0.12)
        opacity: actionMouse.enabled ? 1 : 0.5
        Text {
            textFormat: Text.PlainText
            id: actionText
            anchors.centerIn: parent
            text: root.busy ? "Linking…" : root.action
            color: root.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
        }
        MouseArea {
            id: actionMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            enabled: !root.demo && root.actionEnabled && !root.busy
            onClicked: root.actionRequested()
        }
    }
}
