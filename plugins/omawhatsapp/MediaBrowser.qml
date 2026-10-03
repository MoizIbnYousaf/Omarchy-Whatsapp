import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "MediaModel.js" as MediaModel
import "LinkModel.js" as LinkModel
import "TimeFormat.js" as TimeFormat

// Media, links and docs of one chat, over its whole local history, in their
// own view. The conversation is never filtered; closing this goes back to it.
Rectangle {
  id: root
  objectName: "mediaBrowser"

  property var items: []
  property string kind: "media"
  property bool loading: false
  property color foreground: Color.foreground
  property color surface: Color.background
  property color accent: Color.accent
  property color muted: foreground
  property string fontFamily: Style.font.family
  readonly property var mediaItems: kind === "media" ? items : []
  readonly property var linkRows: {
    if (kind !== "links") return []
    var rows = []
    for (var i = 0; i < items.length; i++) {
      var text = String(items[i].text || items[i].media_caption || "")
      LinkModel.extract(text, 5).forEach(function(link) {
        rows.push({ url: link.url, label: link.label || link.url, timestamp: items[i].timestamp,
          sender: String(items[i].sender || ""), id: items[i].id })
      })
    }
    return rows
  }
  readonly property var docItems: kind === "docs" ? items : []
  signal closeRequested()
  signal kindRequested(string kind)
  signal openMediaRequested(var item, var gallery)
  signal openDocumentRequested(var item)
  signal downloadRequested(var item)

  function dateText(ts) {
    var value = Number(ts || 0)
    return value > 0 ? TimeFormat.dayLabel(value) : ""
  }
  function fileUrl(path) { return MediaModel.encodedFileUrl(String(path || "")) }
  function humanSize(bytes) {
    var value = Number(bytes || 0)
    if (value <= 0) return ""
    if (value < 1024 * 1024) return Math.max(1, Math.round(value / 1024)) + " KB"
    return (value / 1024 / 1024).toFixed(1) + " MB"
  }
  function openMedia(item) {
    if (String(item.local_path || "") === "") { downloadRequested(item); return }
    var gallery = mediaItems.filter(function(entry) { return String(entry.local_path || "") !== "" })
    openMediaRequested(item, gallery)
  }

  color: surface

  // Owns every click, hover and wheel inside the panel: without it, a right
  // click on a participant reached the message bubble underneath and opened
  // that message's menu.
  MouseArea {
    objectName: "panelPointerGuard"
    anchors.fill: parent
    z: -1
    acceptedButtons: Qt.AllButtons
    hoverEnabled: true
    onWheel: function(wheel) { wheel.accepted = true }
  }
  Rectangle {
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    anchors.left: parent.left
    width: 1
    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
  }

  Item {
    id: header
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    height: Style.space(54)
    Text {
      textFormat: Text.PlainText
      anchors.left: parent.left
      anchors.leftMargin: Style.space(18)
      anchors.verticalCenter: parent.verticalCenter
      text: "Media, links and docs"
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }
    PanelActionButton {
      objectName: "mediaBrowserClose"
      anchors.right: parent.right
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      iconText: "󰅖"
      tooltipText: "Back to the conversation · Esc"
      foreground: root.muted
      hoverColor: root.foreground
      fontFamily: root.fontFamily
      fontSize: Style.font.body
      size: Style.space(30)
      onClicked: root.closeRequested()
    }
  }

  Row {
    id: tabs
    anchors.top: header.bottom
    anchors.left: parent.left
    anchors.leftMargin: Style.space(14)
    spacing: Style.space(6)
    Repeater {
      model: [{ id: "media", label: "Media" }, { id: "links", label: "Links" }, { id: "docs", label: "Docs" }]
      delegate: Rectangle {
        required property var modelData
        objectName: "mediaBrowserTab-" + modelData.id
        readonly property bool active: root.kind === modelData.id
        width: tabText.implicitWidth + Style.space(22)
        height: Style.space(28)
        radius: height / 2
        color: active ? Style.selectedFillFor(root.foreground, root.accent)
          : (tabHover.hovered ? Style.hoverFillFor(root.foreground, root.accent)
            : Style.normalFillFor(root.foreground, root.accent))
        Text {
          textFormat: Text.PlainText
          id: tabText
          anchors.centerIn: parent
          text: modelData.label
          color: parent.active ? root.foreground : root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
        HoverHandler { id: tabHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.kindRequested(modelData.id) }
      }
    }
  }

  Item {
    id: body
    anchors.top: tabs.bottom
    anchors.topMargin: Style.space(10)
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.leftMargin: Style.space(10)
    anchors.rightMargin: Style.space(10)

    GridView {
      id: mediaGrid
      objectName: "mediaBrowserGrid"
      visible: root.kind === "media"
      anchors.fill: parent
      clip: true
      cellWidth: Math.floor(width / 3)
      cellHeight: cellWidth
      model: root.mediaItems
      boundsBehavior: Flickable.StopAtBounds
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
      delegate: Rectangle {
        required property var modelData
        readonly property bool local: String(modelData.local_path || "") !== ""
        readonly property bool isVideo: MediaModel.isVideo(modelData)
        width: mediaGrid.cellWidth - Style.space(4)
        height: mediaGrid.cellHeight - Style.space(4)
        radius: Style.cornerRadius
        clip: true
        color: Style.normalFillFor(root.foreground, root.accent)
        Image {
          anchors.fill: parent
          visible: parent.local && !parent.isVideo
          source: visible ? root.fileUrl(modelData.local_path) : ""
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          sourceSize.width: 320
          sourceSize.height: 320
        }
        Text {
          textFormat: Text.PlainText
          anchors.centerIn: parent
          visible: parent.isVideo || !parent.local
          text: parent.local ? "󰐊" : "󰇚"
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.iconLarge
        }
        HoverHandler { id: tileHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.openMedia(modelData) }
        PanelToolTip {
          visible: tileHover.hovered
          text: (parent.local ? "" : "Download · ") + root.dateText(modelData.timestamp)
        }
      }
    }

    ListView {
      id: linkList
      objectName: "mediaBrowserLinks"
      visible: root.kind === "links"
      anchors.fill: parent
      clip: true
      spacing: Style.space(2)
      model: root.linkRows
      boundsBehavior: Flickable.StopAtBounds
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
      delegate: Rectangle {
        required property var modelData
        width: linkList.width
        height: Style.space(52)
        radius: Style.cornerRadius
        color: linkHover.hovered ? Style.hoverFillFor(root.foreground, root.accent) : "transparent"
        Text {
          textFormat: Text.PlainText
          id: linkIcon
          anchors.left: parent.left
          anchors.leftMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          text: "󰌷"
          color: root.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.icon
        }
        Column {
          anchors.left: linkIcon.right
          anchors.leftMargin: Style.space(10)
          anchors.right: parent.right
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: modelData.label
            color: root.foreground
            elide: Text.ElideRight
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: root.dateText(modelData.timestamp) + (modelData.sender !== "" ? " · " + modelData.sender : "")
            color: root.muted
            elide: Text.ElideRight
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
        HoverHandler { id: linkHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: Qt.openUrlExternally(modelData.url) }
        PanelToolTip { visible: linkHover.hovered; text: modelData.url }
      }
    }

    ListView {
      id: docList
      objectName: "mediaBrowserDocs"
      visible: root.kind === "docs"
      anchors.fill: parent
      clip: true
      spacing: Style.space(2)
      model: root.docItems
      boundsBehavior: Flickable.StopAtBounds
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
      delegate: Rectangle {
        required property var modelData
        readonly property bool local: String(modelData.local_path || "") !== ""
        width: docList.width
        height: Style.space(52)
        radius: Style.cornerRadius
        color: docHover.hovered ? Style.hoverFillFor(root.foreground, root.accent) : "transparent"
        Text {
          textFormat: Text.PlainText
          id: docIcon
          anchors.left: parent.left
          anchors.leftMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          text: parent.local ? "󰈙" : "󰇚"
          color: root.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.icon
        }
        Column {
          anchors.left: docIcon.right
          anchors.leftMargin: Style.space(10)
          anchors.right: parent.right
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: String(modelData.filename || "Document")
            color: root.foreground
            elide: Text.ElideMiddle
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: [root.dateText(modelData.timestamp), root.humanSize(modelData.file_size),
              parent.parent.local ? "" : "not downloaded"].filter(function(part) { return part !== "" }).join(" · ")
            color: root.muted
            elide: Text.ElideRight
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
        HoverHandler { id: docHover; cursorShape: Qt.PointingHandCursor }
        TapHandler {
          onTapped: parent.local ? root.openDocumentRequested(modelData) : root.downloadRequested(modelData)
        }
      }
    }

    Text {
      textFormat: Text.PlainText
      objectName: "mediaBrowserEmpty"
      anchors.centerIn: parent
      width: parent.width - Style.space(24)
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
      visible: (root.kind === "media" ? root.mediaItems.length
        : root.kind === "links" ? root.linkRows.length : root.docItems.length) === 0
      text: root.loading ? "Reading this chat's history…"
        : root.kind === "media" ? "No photos or videos in this chat on this computer"
        : root.kind === "links" ? "No links in this chat on this computer"
        : "No documents in this chat on this computer"
      color: root.muted
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }
}
