import QtQuick
import QtQuick.Controls
import qs.Commons

// One WhatsApp-style timeline item: quote, content, interactive options,
// reactions, delivery metadata, and the hover action surface stay together so
// the virtualized conversation remains cheap at any window width.
Item {
  id: root

  required property var message
  required property color foreground
  required property color background
  required property color accent
  required property color dim
  required property color dimmer
  required property string fontFamily
  property bool groupChat: false
  property bool selected: false
  property bool narrow: false
  property bool busyMedia: false

  signal selectedRequested()
  signal openMediaRequested(string path)
  signal downloadMediaRequested()
  signal replyRequested()
  signal reactionRequested(string emoji)
  signal editRequested()
  signal deleteRequested(bool forMe)
  signal forwardRequested()
  signal copyRequested(string text)
  signal optionRequested(int index)

  readonly property string bodyText: {
    if (!message || message["text"] === undefined || message["text"] === null) return ""
    return String(message["text"])
  }
  readonly property string timestampText: Qt.formatDateTime(
    new Date(Number(message.timestamp || 0) * 1000), "h:mm AP")
  readonly property real maximumWidth: width * (narrow ? 0.92 : 0.76)
  readonly property real metadataWidth: timestampMetrics.advanceWidth
    + (message.edited === true ? editedMetrics.advanceWidth + Style.space(6) : 0)
    + (message.starred === true ? Style.space(16) : 0)
    + (message.from_me ? Style.space(16) : 0)
  readonly property real naturalTextWidth: Math.max(
    messageMetrics.advanceWidth,
    senderMetrics.advanceWidth,
    metadataWidth)
  readonly property real desiredWidth: message.media_type
      || String(message.quoted_id || "") !== ""
      || (Array.isArray(message.buttons) && message.buttons.length > 0)
    ? maximumWidth
    : Math.max(Style.space(88), Math.min(maximumWidth,
        naturalTextWidth + Style.space(22)))
  readonly property var reactionPills: {
    var grouped = ({})
    var values = Array.isArray(message.reactions) ? message.reactions : []
    for (var i = 0; i < values.length; i++) {
      var emoji = String(values[i].emoji || "")
      if (emoji === "") continue
      if (!grouped[emoji]) grouped[emoji] = { emoji: emoji, count: 0, mine: false }
      grouped[emoji].count += 1
      grouped[emoji].mine = grouped[emoji].mine || values[i].from_me === true
    }
    return Object.keys(grouped).map(function(key) { return grouped[key] })
  }

  implicitHeight: bubble.height + (reactionRow.visible ? reactionRow.height + Style.space(4) : 0)
  height: implicitHeight

  TextMetrics {
    id: messageMetrics
    text: root.bodyText
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
  }

  TextMetrics {
    id: senderMetrics
    text: !root.message.from_me && root.groupChat
      ? String(root.message.sender || "") : ""
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }

  TextMetrics {
    id: timestampMetrics
    text: root.timestampText
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }

  TextMetrics {
    id: editedMetrics
    text: "edited"
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.italic: true
  }

  Rectangle {
    id: bubble
    anchors.right: root.message.from_me ? parent.right : undefined
    anchors.left: root.message.from_me ? undefined : parent.left
    width: root.desiredWidth
    height: bubbleColumn.implicitHeight + Style.space(18)
    radius: Style.cornerRadius
    color: root.message.from_me
      ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.14)
      : Style.normalFillFor(root.foreground, root.accent)
    border.width: root.selected ? 1 : 0
    border.color: root.accent

    HoverHandler { id: bubbleHover }

    Column {
      id: bubbleColumn
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.margins: Style.space(9)
      spacing: Style.space(6)

      Text {
        textFormat: Text.PlainText
        visible: root.message.forwarded === true
        text: "󰜎  Forwarded"
        color: root.dimmer
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.italic: true
      }

      Text {
        textFormat: Text.PlainText
        visible: !root.message.from_me && root.groupChat
        text: String(root.message.sender || "")
        color: root.accent
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Rectangle {
        visible: String(root.message.quoted_id || "") !== ""
        width: parent.width
        height: quoteColumn.implicitHeight + Style.space(12)
        radius: Style.cornerRadius
        color: Qt.rgba(root.background.r, root.background.g, root.background.b, 0.52)

        Rectangle {
          anchors.left: parent.left
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          width: Style.space(3)
          radius: width / 2
          color: root.accent
        }

        Column {
          id: quoteColumn
          anchors.left: parent.left
          anchors.leftMargin: Style.space(10)
          anchors.right: parent.right
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)
          Text {
            textFormat: Text.PlainText
            text: String(root.message.quoted_sender || "WhatsApp")
            color: root.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
          Text {
            textFormat: Text.PlainText
            id: quoteText
            width: parent.width
            text: String(root.message.quoted_text || "") !== ""
              ? String(root.message.quoted_text)
              : "[" + String(root.message.quoted_media_type || "message") + "]"
            color: root.dim
            elide: Text.ElideRight
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }

      MediaBubble {
        visible: !!root.message.media_type
        width: parent.width
        message: root.message
        foreground: root.foreground
        background: root.background
        accent: root.accent
        dim: root.dim
        dimmer: root.dimmer
        fontFamily: root.fontFamily
        busy: root.busyMedia
        onOpenRequested: function(path) { root.openMediaRequested(path) }
        onDownloadRequested: root.downloadMediaRequested()
      }

      TextEdit {
        id: messageText
        visible: root.bodyText.length > 0
        width: parent.width
        height: contentHeight
        text: root.bodyText
        color: root.foreground
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        readOnly: true
        selectByMouse: true
        persistentSelection: true
        selectionColor: root.accent
        selectedTextColor: root.background
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        onSelectedTextChanged: {
          if (selectedText !== "") selectionCopyDelay.restart()
        }

        Timer {
          id: selectionCopyDelay
          interval: 140
          repeat: false
          onTriggered: {
            var value = String(messageText.selectedText || "")
            if (value !== "") root.copyRequested(value)
          }
        }
      }

      Column {
        visible: Array.isArray(root.message.buttons) && root.message.buttons.length > 0
        width: parent.width
        spacing: Style.space(4)
        Repeater {
          model: Array.isArray(root.message.buttons) ? root.message.buttons : []
          delegate: Rectangle {
            required property var modelData
            required property int index
            width: parent.width
            height: Style.space(34)
            radius: Style.cornerRadius
            color: optionHover.hovered
              ? Style.hoverFillFor(root.foreground, root.accent)
              : Qt.rgba(root.background.r, root.background.g, root.background.b, 0.45)
            Text {
              textFormat: Text.PlainText
              anchors.centerIn: parent
              width: parent.width - Style.space(16)
              text: String(modelData.display_text || "Option " + (index + 1))
              color: root.accent
              horizontalAlignment: Text.AlignHCenter
              elide: Text.ElideRight
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            HoverHandler { id: optionHover }
            TapHandler { onTapped: root.optionRequested(index + 1) }
          }
        }
      }

      Row {
        anchors.right: parent.right
        spacing: Style.space(6)
        Text {
          textFormat: Text.PlainText
          visible: root.message.edited === true
          text: "edited"
          color: root.dimmer
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.italic: true
        }
        Text {
          textFormat: Text.PlainText
          visible: root.message.starred === true
          text: "󰓎"
          color: root.dimmer
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
        Text {
          textFormat: Text.PlainText
          text: root.timestampText
          color: root.dimmer
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
        Text {
          textFormat: Text.PlainText
          visible: root.message.from_me
          text: "✓"
          color: root.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }

    Rectangle {
      id: actionSurface
      visible: bubbleHover.hovered || reactionPicker.opened || actionMenu.opened
      anchors.top: parent.top
      anchors.topMargin: Style.space(5)
      anchors.right: root.message.from_me ? undefined : parent.right
      anchors.left: root.message.from_me ? parent.left : undefined
      anchors.rightMargin: Style.space(5)
      anchors.leftMargin: Style.space(5)
      width: actionRow.implicitWidth + Style.space(8)
      height: Style.space(28)
      radius: height / 2
      color: Qt.rgba(root.background.r, root.background.g, root.background.b, 0.92)
      border.width: 1
      border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)

      Row {
        id: actionRow
        anchors.centerIn: parent
        spacing: Style.space(1)
        Repeater {
          model: [
            { icon: "󰜸", action: "reply", hint: "Reply" },
            { icon: "󰋇", action: "react", hint: "React" },
            { icon: "󰇙", action: "more", hint: "More" }
          ]
          delegate: Rectangle {
            required property var modelData
            width: Style.space(24)
            height: width
            radius: width / 2
            color: actionHover.hovered
              ? Style.hoverFillFor(root.foreground, root.accent) : "transparent"
            Text {
              textFormat: Text.PlainText
              anchors.centerIn: parent
              text: modelData.icon
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            HoverHandler { id: actionHover }
            TapHandler {
              onTapped: {
                root.selectedRequested()
                if (modelData.action === "reply") root.replyRequested()
                else if (modelData.action === "react") reactionPicker.open()
                else actionMenu.open()
              }
            }
          }
        }
      }
    }

    MouseArea {
      anchors.fill: parent
      z: -1
      onClicked: root.selectedRequested()
    }

    Popup {
      id: reactionPicker
      x: Math.max(0, Math.min(bubble.width - width, actionSurface.x))
      y: actionSurface.y + actionSurface.height + Style.space(3)
      width: emojiRow.implicitWidth + Style.space(12)
      height: Style.space(38)
      padding: 0
      closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
      background: Rectangle {
        radius: height / 2
        color: root.background
        border.width: 1
        border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.16)
      }
      contentItem: Row {
        id: emojiRow
        anchors.centerIn: parent
        spacing: Style.space(3)
        Repeater {
          model: ["👍", "❤️", "😂", "😮", "😢", "🙏"]
          delegate: Rectangle {
            required property string modelData
            width: Style.space(30)
            height: width
            radius: width / 2
            color: emojiHover.hovered
              ? Style.hoverFillFor(root.foreground, root.accent) : "transparent"
            Text {
              textFormat: Text.PlainText
              anchors.centerIn: parent
              text: modelData
              font.pixelSize: Style.font.body
            }
            HoverHandler { id: emojiHover }
            TapHandler {
              onTapped: {
                reactionPicker.close()
                root.reactionRequested(modelData)
              }
            }
          }
        }
      }
    }

    Popup {
      id: actionMenu
      x: Math.max(0, bubble.width - width)
      y: actionSurface.y + actionSurface.height + Style.space(3)
      width: Style.space(178)
      height: menuColumn.implicitHeight + Style.space(10)
      padding: Style.space(5)
      closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
      background: Rectangle {
        radius: Style.cornerRadius
        color: root.background
        border.width: 1
        border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.16)
      }
      contentItem: Column {
        id: menuColumn
        spacing: Style.space(2)
        Repeater {
          model: [
            { label: "Reply", action: "reply", show: true },
            { label: "Copy text", action: "copy", show: root.bodyText !== "" },
            { label: "Edit", action: "edit", show: root.message.from_me && !root.message.media_type },
            { label: "Forward", action: "forward", show: true },
            { label: "Delete for me", action: "delete-me", show: true },
            { label: "Delete for everyone", action: "delete-all", show: root.message.from_me }
          ]
          delegate: Rectangle {
            required property var modelData
            visible: modelData.show
            width: parent.width
            height: visible ? Style.space(32) : 0
            radius: Style.cornerRadius
            color: menuHover.hovered
              ? Style.hoverFillFor(root.foreground, root.accent) : "transparent"
            Text {
              textFormat: Text.PlainText
              anchors.left: parent.left
              anchors.leftMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.label
              color: modelData.action.indexOf("delete") === 0 ? Color.urgent : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            HoverHandler { id: menuHover }
            TapHandler {
              onTapped: {
                actionMenu.close()
                if (modelData.action === "reply") root.replyRequested()
                else if (modelData.action === "copy") root.copyRequested(root.bodyText)
                else if (modelData.action === "edit") root.editRequested()
                else if (modelData.action === "forward") root.forwardRequested()
                else root.deleteRequested(modelData.action === "delete-me")
              }
            }
          }
        }
      }
    }
  }

  Row {
    id: reactionRow
    visible: root.reactionPills.length > 0
    anchors.top: bubble.bottom
    anchors.topMargin: -Style.space(3)
    anchors.right: root.message.from_me ? bubble.right : undefined
    anchors.left: root.message.from_me ? undefined : bubble.left
    height: visible ? Style.space(24) : 0
    spacing: Style.space(4)

    Repeater {
      model: root.reactionPills
      delegate: Rectangle {
        required property var modelData
        width: reactionText.implicitWidth + Style.space(10)
        height: Style.space(24)
        radius: height / 2
        color: modelData.mine
          ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.22)
          : root.background
        border.width: 1
        border.color: modelData.mine ? root.accent
          : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.14)
        Text {
          textFormat: Text.PlainText
          id: reactionText
          anchors.centerIn: parent
          text: modelData.emoji + (modelData.count > 1 ? " " + modelData.count : "")
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
        TapHandler { onTapped: root.reactionRequested(modelData.mine ? "" : modelData.emoji) }
      }
    }
  }
}
