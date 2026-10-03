import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "EmojiModel.js" as EmojiModel

// Emoji picker for both composers. It reads Omarchy's own emoji list and
// inserts at the field's cursor, so the clipboard is never touched and the
// choice lands in the exact draft it was opened from. As on the phone, it
// stays open for as many emoji as wanted and groups them by theme.
Popup {
  id: root
  objectName: "emojiPicker"

  property var target: null
  property color foreground: Color.foreground
  // Named surface, because Popup already owns `background`.
  property color surface: Color.background
  property color accent: Color.accent
  // Popup already owns `dim` too.
  property color muted: foreground
  property string fontFamily: Style.font.family
  property var emojis: []
  property string query: ""
  property var recent: []
  readonly property string dataPath: String(Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy")
    + "/shell/plugins/emojis/emojis.json"
  readonly property var results: EmojiModel.filter(emojis, query, 400)
  // Browsing: every theme under its header, recent ones first. Searching:
  // just the matches.
  readonly property var laidOut: EmojiModel.layout(emojis, recent, 8)
  readonly property var shown: query === "" ? laidOut.items : results
  readonly property var firstEmoji: {
    for (var i = 0; i < shown.length; i++)
      if (shown[i].kind === undefined || shown[i].kind === "emoji") return shown[i].e
    return ""
  }
  property string currentSection: laidOut.sections.length > 0 ? laidOut.sections[0].id : ""
  function showSection(id) {
    var sections = laidOut.sections
    for (var i = 0; i < sections.length; i++) {
      if (sections[i].id !== id) continue
      grid.positionViewAtIndex(sections[i].index, GridView.Beginning)
      currentSection = id
      return true
    }
    return false
  }
  signal picked(string emoji)
  // Stickers tab: recent stickers of this account; picking one sends it.
  property bool stickersEnabled: false
  property var stickers: []
  property bool stickersLoading: false
  property string tab: "emoji"
  signal stickerPicked(string path)
  signal stickersOpened()
  function showTab(name) {
    tab = name === "stickers" && stickersEnabled ? "stickers" : "emoji"
    if (tab === "stickers") stickersOpened()
    else Qt.callLater(function() { searchField.forceActiveFocus() })
  }
  function chooseSticker(path) {
    var value = String(path || "")
    if (value === "") return false
    stickerPicked(value)
    close()
    return true
  }

  width: Style.space(344)
  height: Style.space(360)
  padding: Style.space(8)
  closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
  onOpened: {
    query = ""
    searchField.text = ""
    if (tab === "stickers" && stickersEnabled) stickersOpened()
    else { tab = "emoji"; searchField.forceActiveFocus() }
  }

  function choose(emoji) {
    var value = String(emoji || "")
    if (value === "") return false
    if (target && typeof target.insert === "function") {
      var position = Number(target.cursorPosition || 0)
      target.insert(position, value)
      target.cursorPosition = position + value.length
    }
    recent = EmojiModel.remember(recent, value, 16)
    picked(value)
    // It stays open for the next one; Esc, a click outside, the emoji button
    // or the close button put it away.
    return true
  }

  FileView {
    path: root.dataPath
    onLoaded: root.emojis = EmojiModel.parse(text())
  }

  background: Rectangle {
    radius: Style.cornerRadius
    color: root.surface
    border.width: 1
    border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.16)
  }

  contentItem: Item {
    Row {
      id: tabs
      objectName: "pickerTabs"
      visible: root.stickersEnabled
      anchors.top: parent.top
      anchors.left: parent.left
      height: visible ? Style.space(28) : 0
      spacing: Style.space(4)
      Repeater {
        model: [{ id: "emoji", label: "Emoji" }, { id: "stickers", label: "Stickers" }]
        delegate: Rectangle {
          required property var modelData
          objectName: "pickerTab-" + modelData.id
          readonly property bool active: root.tab === modelData.id
          width: tabLabel.implicitWidth + Style.space(20)
          height: Style.space(26)
          radius: height / 2
          color: active ? Style.selectedFillFor(root.foreground, root.accent)
            : (tabHover.hovered ? Style.hoverFillFor(root.foreground, root.accent) : "transparent")
          Text {
            textFormat: Text.PlainText
            id: tabLabel
            anchors.centerIn: parent
            text: modelData.label
            color: parent.active ? root.foreground : root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
          HoverHandler { id: tabHover; cursorShape: Qt.PointingHandCursor }
          TapHandler { onTapped: root.showTab(modelData.id) }
        }
      }
    }
    GridView {
      id: stickerGrid
      objectName: "stickerGrid"
      visible: root.tab === "stickers"
      anchors.top: tabs.bottom
      anchors.topMargin: Style.space(6)
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      clip: true
      cellWidth: Math.floor(width / 4)
      cellHeight: cellWidth
      model: root.stickers
      boundsBehavior: Flickable.StopAtBounds
      delegate: Rectangle {
        required property var modelData
        width: stickerGrid.cellWidth
        height: stickerGrid.cellHeight
        radius: Style.cornerRadius
        color: stickerHover.hovered ? Style.hoverFillFor(root.foreground, root.accent) : "transparent"
        AnimatedImage {
          anchors.fill: parent
          anchors.margins: Style.space(4)
          source: "file://" + String(modelData.path || "").split("/").map(function(part) {
            return encodeURIComponent(part) }).join("/")
          fillMode: Image.PreserveAspectFit
          asynchronous: true
          smooth: true
          playing: stickerHover.hovered
        }
        HoverHandler { id: stickerHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.chooseSticker(modelData.path) }
      }
    }
    Text {
      textFormat: Text.PlainText
      objectName: "stickerEmpty"
      visible: root.tab === "stickers" && root.stickers.length === 0
      anchors.centerIn: stickerGrid
      width: stickerGrid.width - Style.space(24)
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
      text: root.stickersLoading ? "Loading stickers…"
        : "No stickers on this computer yet. Stickers you send or receive show up here."
      color: root.muted
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
    TextField {
      id: searchField
      objectName: "emojiSearch"
      visible: root.tab === "emoji"
      anchors.top: tabs.bottom
      anchors.left: parent.left
      anchors.right: closeButton.left
      anchors.rightMargin: Style.space(4)
      placeholderText: "Search emoji"
      foreground: root.foreground
      accent: root.accent
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      onTextChanged: root.query = text
      Keys.onReturnPressed: if (root.firstEmoji !== "") root.choose(root.firstEmoji)
      Keys.onEnterPressed: if (root.firstEmoji !== "") root.choose(root.firstEmoji)
    }
    PanelActionButton {
      id: closeButton
      objectName: "emojiPickerClose"
      anchors.right: parent.right
      anchors.top: tabs.bottom
      size: searchField.visible ? searchField.height : Style.space(28)
      iconText: "󰅖"
      tooltipText: "Close · Esc"
      foreground: root.muted
      hoverColor: root.foreground
      fontFamily: root.fontFamily
      fontSize: Style.font.bodySmall
      onClicked: root.close()
    }
    Row {
      id: sectionTabs
      objectName: "emojiSections"
      visible: root.tab === "emoji" && root.query === ""
      anchors.top: searchField.bottom
      anchors.topMargin: Style.space(4)
      anchors.left: parent.left
      anchors.right: parent.right
      height: visible ? Style.space(28) : 0
      Repeater {
        model: root.laidOut.sections
        delegate: Rectangle {
          required property var modelData
          objectName: "emojiSection-" + modelData.id
          readonly property bool active: root.currentSection === modelData.id
          width: Math.floor(sectionTabs.width / Math.max(1, root.laidOut.sections.length))
          height: Style.space(28)
          radius: Style.cornerRadius
          color: active ? Style.selectedFillFor(root.foreground, root.accent)
            : (sectionHover.hovered ? Style.hoverFillFor(root.foreground, root.accent) : "transparent")
          Text {
            textFormat: Text.PlainText
            anchors.centerIn: parent
            text: modelData.icon
            opacity: parent.active ? 1 : 0.6
            font.pixelSize: Style.font.bodySmall
          }
          HoverHandler { id: sectionHover; cursorShape: Qt.PointingHandCursor }
          PanelToolTip { visible: sectionHover.hovered; text: modelData.label }
          TapHandler { onTapped: root.showSection(modelData.id) }
        }
      }
    }
    GridView {
      id: grid
      objectName: "emojiGrid"
      visible: root.tab === "emoji"
      anchors.top: sectionTabs.bottom
      anchors.topMargin: Style.space(6)
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      clip: true
      cellWidth: Math.floor(width / 8)
      cellHeight: cellWidth
      model: root.shown
      boundsBehavior: Flickable.StopAtBounds
      // The theme tab follows the scroll.
      onContentYChanged: if (root.query === "") root.currentSection = EmojiModel.sectionAt(
        root.laidOut.sections, indexAt(1, contentY + cellHeight / 2))
      delegate: Item {
        id: cell
        required property var modelData
        readonly property string kind: String(modelData.kind || "emoji")
        width: grid.cellWidth
        height: grid.cellHeight
        // A header is one cell wide but draws across its whole row.
        Text {
          textFormat: Text.PlainText
          objectName: "emojiSectionHeader"
          visible: cell.kind === "header"
          anchors.left: parent.left
          anchors.leftMargin: Style.space(4)
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Style.space(4)
          width: grid.width - Style.space(8)
          text: String(cell.modelData.label || "")
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
        Rectangle {
          visible: cell.kind === "emoji"
          anchors.fill: parent
          radius: Style.cornerRadius
          color: emojiHover.hovered ? Style.hoverFillFor(root.foreground, root.accent) : "transparent"
          Text {
            textFormat: Text.PlainText
            anchors.centerIn: parent
            text: String(cell.modelData.e || "")
            font.pixelSize: Style.font.icon
          }
          HoverHandler { id: emojiHover; cursorShape: Qt.PointingHandCursor }
          TapHandler { onTapped: root.choose(cell.modelData.e) }
        }
      }
    }
    Text {
      textFormat: Text.PlainText
      visible: root.tab === "emoji" && root.shown.length === 0
      anchors.centerIn: grid
      text: "No emoji matches"
      color: root.muted
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }
}
