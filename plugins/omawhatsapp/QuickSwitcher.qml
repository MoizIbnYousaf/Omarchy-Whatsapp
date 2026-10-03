import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "AccountModel.js" as AccountModel

// Ctrl+K: jump to any chat by typing part of its name. Arrows move, Enter
// opens, Esc closes. Archived chats are found too, as in a search.
Popup {
  id: root
  objectName: "quickSwitcher"

  property var chats: []
  property bool showAvatars: true
  property color foreground: Color.foreground
  property color surface: Color.background
  property color accent: Color.accent
  property color muted: foreground
  property string fontFamily: Style.font.family
  property string query: ""
  property int cursor: 0
  readonly property var results: AccountModel.filterChats(chats, "", query, 12, "all")
  signal chosen(var chat)

  parent: Overlay.overlay
  x: parent ? Math.round((parent.width - width) / 2) : 0
  y: parent ? Math.round(parent.height * 0.14) : 0
  width: Math.min(Style.space(460), (parent ? parent.width : Style.space(480)) - Style.space(28))
  height: Math.min(field.height + list.contentHeight + Style.space(34),
    (parent ? parent.height : Style.space(600)) * 0.7)
  padding: Style.space(10)
  modal: true
  focus: true
  closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
  onOpened: {
    field.text = ""
    query = ""
    cursor = 0
    Qt.callLater(function() { field.forceActiveFocus() })
  }
  onQueryChanged: cursor = 0

  function move(delta) {
    if (results.length === 0) return
    cursor = Math.max(0, Math.min(results.length - 1, cursor + delta))
    list.positionViewAtIndex(cursor, ListView.Contain)
  }
  function accept(index) {
    var chat = results[index === undefined ? cursor : index]
    if (!chat) return false
    chosen(chat)
    close()
    return true
  }

  background: Rectangle {
    radius: Style.cornerRadius
    color: root.surface
    border.width: 1
    border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)
  }

  contentItem: Item {
    TextField {
      id: field
      objectName: "quickSwitcherField"
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      placeholderText: "Go to chat"
      foreground: root.foreground
      accent: root.accent
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      onTextChanged: root.query = text.trim()
      Keys.onUpPressed: root.move(-1)
      Keys.onDownPressed: root.move(1)
      Keys.onReturnPressed: root.accept()
      Keys.onEnterPressed: root.accept()
      Keys.onTabPressed: root.move(1)
    }
    ListView {
      id: list
      objectName: "quickSwitcherList"
      anchors.top: field.bottom
      anchors.topMargin: Style.space(8)
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      clip: true
      spacing: Style.space(2)
      model: root.results
      currentIndex: root.cursor
      boundsBehavior: Flickable.StopAtBounds
      delegate: Rectangle {
        required property var modelData
        required property int index
        width: list.width
        height: Style.space(42)
        radius: Style.cornerRadius
        color: index === root.cursor ? Style.selectedFillFor(root.foreground, root.accent)
          : (rowHover.hovered ? Style.hoverFillFor(root.foreground, root.accent) : "transparent")
        ChatAvatar {
          id: rowAvatar
          anchors.left: parent.left
          anchors.leftMargin: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(28)
          height: width
          showPhoto: root.showAvatars
          chat: modelData
          foreground: root.foreground
          background: root.surface
          accent: root.accent
          fontFamily: root.fontFamily
        }
        Text {
          textFormat: Text.PlainText
          anchors.left: rowAvatar.right
          anchors.leftMargin: Style.space(10)
          anchors.right: badge.left
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          text: String(modelData.name || "WhatsApp chat")
            + (modelData.archived ? "  · archived" : "")
          color: root.foreground
          elide: Text.ElideRight
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
        Text {
          textFormat: Text.PlainText
          id: badge
          anchors.right: parent.right
          anchors.rightMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          text: Number(modelData.unread || 0) > 0 ? String(modelData.unread) : ""
          color: root.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
        HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.accept(index) }
      }
    }
  }
}
