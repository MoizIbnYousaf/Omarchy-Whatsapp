import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui as Ui
import "FormatModel.js" as FormatModel
import "MediaModel.js" as MediaModel
import "TimeFormat.js" as TimeFormat
import "LinkModel.js" as LinkModel
import "Tint.js" as Tint

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
  property bool surfaceActive: true
  property string activePlaybackId: ""
  // The timeline's audio player, handed to voice notes (see TimelineAudio).
  property var sharedAudio: null
  property real audioRate: 1
  signal audioRateRequested(real rate)
  property string timeFormat: "auto"

  signal selectedRequested()
  signal openMediaRequested(string path)
  signal downloadMediaRequested()
  signal replyRequested()
  signal reactionRequested(string emoji)
  signal editRequested()
  signal deleteRequested(bool forMe)
  signal forwardRequested()
  // Star or unstar on every linked device; offered where the surface can.
  signal starRequested(bool starred)
  property bool starEnabled: false
  signal copyRequested(string text)
  signal saveRequested()
  // Retry or discard a message that failed to send.
  signal pendingSendRequested(string action)

  // Neighbours from the same person, as the timeline sees them: the bubble
  // tightens its corners where they join and names the sender once.
  property bool joinsAbove: false
  property bool joinsBelow: false
  // One color per person in a group, derived from the theme's accent so it
  // follows the theme: the same hue turned, same strength.
  function senderColor(key) {
    return Tint.personColor(key, root.accent)
  }

  // Sent from here, not yet stored by the mirror: shown at once, with no
  // actions that need a WhatsApp message id.
  readonly property bool pending: message && message.pending === true
  // Deleted for everyone: a placeholder, as on the phone, with no content.
  readonly property bool revoked: message && message.revoked === true
  // Lists inside a message reach the bubble as Qt sequences once they pass
  // through a list model, so Array.isArray is false for them; copy them.
  function listOf(value) {
    if (!value || typeof value === "string") return []
    var count = Number(value.length || 0)
    var items = []
    for (var i = 0; i < count; i++) items.push(value[i])
    return items
  }
  readonly property var buttonItems: listOf(message ? message.buttons : null)
  // A shared contact, as wacli stores it, becomes a card like the phone's.
  readonly property var contactCards: listOf(message ? message.contacts : null)
  signal contactChatRequested(var card)
  // WhatsApp's *bold*, _italic_, ~strike~, code and lists. FormatModel
  // escapes the whole text first and emits only its own fixed tags.
  readonly property bool richBody: bodyText !== "" && FormatModel.hasFormatting(bodyText)
  readonly property string bodyHtml: richBody ? FormatModel.toHtml(bodyText, {
    dim: String(dim),
    code: String(Qt.rgba(foreground.r, foreground.g, foreground.b, 0.14))
  }) : ""
  readonly property var poll: message && message.poll ? message.poll : null
  readonly property var pollOptions: poll ? listOf(poll.options) : []
  readonly property int pollMostVotes: pollOptions.reduce(function(most, option) {
    return Math.max(most, Number(option.votes || 0)) }, 0)
  signal pollVoteRequested(var options)
  // A single-choice poll takes the tapped option; a multiple-choice one adds
  // or drops it from your current choices. WhatsApp keeps at least one.
  function votePollOption(text) {
    if (!poll || pending) return false
    var value = String(text || "")
    var mine = pollOptions.filter(function(option) { return option.mine === true })
      .map(function(option) { return String(option.text) })
    var next = [value]
    if (Number(poll.selectable || 1) > 1) {
      var at = mine.indexOf(value)
      next = at >= 0 ? mine.filter(function(option) { return option !== value })
        : mine.concat([value])
      if (next.length > Number(poll.selectable)) return false
    } else if (mine.length === 1 && mine[0] === value) return false
    if (next.length === 0) return false
    pollVoteRequested(next)
    return true
  }
  // While its actions or menus are showing, the row must draw above its
  // neighbours: lists stack delegates in creation order, not by position.
  readonly property bool raised: actionSurface.visible || reactionPicker.opened
    || actionMenu.opened
  // The message menu, as data: tests and the right-click path share it.
  readonly property bool sendFailed: pending && message.send_state === "failed"
  readonly property var menuActions: sendFailed
    ? [{ label: "Try again", action: "retry-send", show: true },
       { label: "Copy text", action: "copy", show: true },
       { label: "Discard", action: "discard-send", show: true }]
    : pending
    ? [{ label: "Copy text", action: "copy", show: true }]
    : revoked ? [{ label: "Delete for me", action: "delete-me", show: true }]
    : [
    { label: "Reply", action: "reply", show: true },
    { label: "React", action: "react", show: true },
    { label: "Copy text", action: "copy", show: root.bodyText !== "" },
    { label: "Copy link", action: "copy-link", show: root.links.length > 0 },
    { label: "Edit", action: "edit", show: root.message.from_me && !root.message.media_type },
    { label: "Save as…", action: "save", show: root.hasMedia },
    { label: "Forward", action: "forward", show: true },
    { label: root.message.starred === true ? "Unstar" : "Star", action: "star",
      show: root.starEnabled },
    { label: "Delete for me", action: "delete-me", show: true },
    { label: "Delete for everyone", action: "delete-all", show: root.message.from_me }
  ].filter(function(item) { return item.show })
  function runMenuAction(action) {
    actionMenu.close()
    if (action === "reply") root.replyRequested()
    else if (action === "react") reactionPicker.open()
    else if (action === "copy") root.copyRequested(root.bodyText)
    else if (action === "copy-link") root.copyRequested(root.links[0].url)
    else if (action === "edit") root.editRequested()
    else if (action === "forward") root.forwardRequested()
    else if (action === "star") root.starRequested(root.message.starred !== true)
    else if (action === "save") root.saveRequested()
    else if (action === "retry-send") root.pendingSendRequested("retry")
    else if (action === "discard-send") root.pendingSendRequested("discard")
    else root.deleteRequested(action === "delete-me")
  }
  signal optionRequested(int index)
  signal playbackRequested(string messageId)

  readonly property string bodyText: {
    if (!message || message["text"] === undefined || message["text"] === null) return ""
    return String(message["text"])
  }
  readonly property var links: LinkModel.extract(bodyText, 3)
  readonly property string fullTimestampText: Qt.formatDateTime(
    new Date(Number(message.timestamp || 0) * 1000),
    Qt.locale().dateFormat(Locale.LongFormat) + " · "
      + TimeFormat.clockPattern(timeFormat, Qt.locale().timeFormat(Locale.ShortFormat)))
  readonly property string timestampText: Qt.formatDateTime(
    new Date(Number(message.timestamp || 0) * 1000),
    TimeFormat.clockPattern(timeFormat, Qt.locale().timeFormat(Locale.ShortFormat)))
  // In a group, others' messages keep a column for who wrote them: their photo
  // or initials, next to the last message of each run.
  property bool senderAvatars: false
  property string senderAvatarPath: ""
  readonly property bool senderGutter: senderAvatars && groupChat && message
    && message.from_me !== true
  readonly property real gutterWidth: senderGutter ? Style.space(40) : 0
  readonly property real maximumWidth: (width - gutterWidth) * (narrow ? 0.92 : 0.76)
  // Delivery state of a sent message, from wacli builds that keep receipts;
  // empty when wacli recorded none (official wacli, or older messages).
  readonly property string deliveryStatus: message && message.from_me === true
    && !pending && !revoked ? String(message.status || "") : ""
  readonly property bool showsTicks: ["pending", "sent", "delivered", "read", "played", "error"]
    .indexOf(deliveryStatus) >= 0
  readonly property real metadataWidth: timestampMetrics.advanceWidth
    + (message.edited === true ? editedMetrics.advanceWidth + Style.space(6) : 0)
    + (message.starred === true ? Style.space(16) : 0)
    + (showsTicks ? Style.space(18) : 0)
    + (pending ? Style.space(16) : 0)
  // Room for a short text and its time on one line.
  readonly property real naturalTextWidth: Math.max(
    messageMetrics.advanceWidth + Style.space(10) + metadataWidth,
    senderMetrics.advanceWidth)
  // The text ends the bubble and its last line leaves room for the time.
  readonly property bool textEndsBubble: messageText.visible && links.length === 0
    && buttonItems.length === 0 && poll === null && contactCards.length === 0
  readonly property real lastLineEnd: {
    // Named so the binding follows the text's layout.
    var layout = [messageText.width, messageText.contentHeight, messageText.text]
    return textEndsBubble && layout.length > 0
      ? messageText.positionToRectangle(messageText.length).x : 0
  }
  // A photo, GIF, video or album fills the bubble with a thin frame.
  readonly property bool visualMedia: hasMedia && !sticker
    && (MediaModel.isVisual(message) || String(message.media_type || "") === "album")
    && mediaBubble.mediaKind !== "missing"
  // With no caption the time goes over the picture, as on the phone.
  readonly property bool metaOverMedia: visualMedia && bodyText.length === 0
  readonly property color metaColor: metaOverMedia ? Qt.rgba(1, 1, 1, 0.92) : dimmer
  // A voice note's own bottom row leaves its right end to the time.
  readonly property bool metaInAudio: hasMedia && bodyText.length === 0
    && (mediaBubble.mediaKind === "audio")
  // A portrait photo gets a narrower bubble instead of a cropped strip.
  readonly property real fittedMediaWidth: {
    var w = mediaBubble.decodedMediaWidth
    var h = mediaBubble.decodedMediaHeight
    if (!visualMedia || mediaBubble.album || !(w > 0 && h > 0)) return mediaWidth
    return Math.max(Style.space(200), Math.min(mediaWidth, 315 * w / h + Style.space(8)))
  }
  readonly property bool metaInline: !sticker && textEndsBubble
    && lastLineEnd + Style.space(10) + messageMeta.width <= messageText.width
  readonly property bool hasMedia: String(message.media_type || "") !== ""
  // Stickers stand on their own, as on the phone: no bubble, a fixed size.
  readonly property bool sticker: String(message.media_type || "") === "sticker"
    && String(message.quoted_id || "") === ""
  readonly property real mediaWidth: Math.min(maximumWidth,
    MediaModel.isVisual(message) ? 560 : 520)
  readonly property real desiredWidth: sticker ? Style.space(176) : message.media_type
      || String(message.quoted_id || "") !== ""
      || buttonItems.length > 0 || poll !== null || revoked || contactCards.length > 0
    ? (hasMedia ? fittedMediaWidth : maximumWidth)
    : Math.max(Style.space(88), Math.min(maximumWidth,
        naturalTextWidth + Style.space(22)))
  readonly property var reactionPills: {
    var grouped = ({})
    var values = listOf(message ? message.reactions : null)
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

  // The whole row, not only the bubble, reveals the actions: they sit beside
  // the bubble when there is room, and the pointer must be able to reach them.
  HoverHandler { id: rowHover }

  // Right-click opens the same actions at the pointer; the hover "More"
  // button opens them under the action strip.
  property bool menuAtPointer: false
  property point menuPoint: Qt.point(0, 0)
  function openContextMenu(x, y) {
    menuAtPointer = true
    menuPoint = Qt.point(x, y)
    root.selectedRequested()
    actionMenu.open()
  }

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
    objectName: "messageBubbleSurface"
    opacity: root.pending ? 0.72 : 1
    anchors.right: root.message.from_me ? parent.right : undefined
    anchors.left: root.message.from_me ? undefined : parent.left
    anchors.leftMargin: root.gutterWidth
    width: root.desiredWidth
    // Time and ticks share the last line of text when it has room, as on
    // the phone, instead of taking a line of their own.
    height: (root.visualMedia ? Style.space(4) : Style.space(9)) + bubbleColumn.implicitHeight + (root.sticker
      ? messageMeta.height + Style.space(4)
      : root.metaOverMedia ? Style.space(4)
      : root.metaInAudio ? Style.space(9)
      : root.metaInline ? Style.space(9) : messageMeta.height + Style.space(11))
    // Rounded, with a tight corner on the sender's side where messages of
    // one person join and at the bottom of the last one, in place of a tail.
    readonly property real roundCorner: Style.space(12)
    readonly property real tightCorner: Style.space(4)
    radius: roundCorner
    topLeftRadius: !root.message.from_me && root.joinsAbove ? tightCorner : roundCorner
    bottomLeftRadius: root.message.from_me ? roundCorner : tightCorner
    topRightRadius: root.message.from_me && root.joinsAbove ? tightCorner : roundCorner
    bottomRightRadius: root.message.from_me ? tightCorner : roundCorner
    // A deleted message keeps only an outline where it was.
    color: root.sticker || root.revoked ? "transparent" : root.message.from_me
      ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.16)
      : Style.normalFillFor(root.foreground, root.accent)
    border.width: root.selected || root.revoked ? 1 : 0
    border.color: root.selected ? root.accent
      : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)


    Column {
      id: bubbleColumn
      objectName: "messageBubbleContent"
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      // A photo or video gets a thin frame; text keeps its padding.
      anchors.margins: root.visualMedia ? Style.space(4) : Style.space(9)
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
        objectName: "messageSender"
        visible: !root.message.from_me && root.groupChat && !root.joinsAbove
        text: String(root.message.sender || "")
        color: root.senderColor(root.message.sender_jid || root.message.sender)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.weight: Font.DemiBold
      }

      Rectangle {
        visible: String(root.message.quoted_id || "") !== ""
        width: parent.width
        height: quoteColumn.implicitHeight + Style.space(12)
        objectName: "messageQuote"
        radius: Style.space(8)
        color: Qt.rgba(root.background.r, root.background.g, root.background.b, 0.42)

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
            objectName: "messageQuoteAuthor"
            text: String(root.message.quoted_sender || "WhatsApp")
            color: String(root.message.quoted_sender || "") === "You" ? root.accent
              : root.senderColor(root.message.quoted_sender)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.weight: Font.DemiBold
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
        id: mediaBubble
        objectName: "mediaBubble"
        visible: !!root.message.media_type
        width: parent.width
        message: root.message
        cornerColor: root.sticker ? root.background : Qt.tint(root.background, bubble.color)
        foreground: root.foreground
        background: root.background
        accent: root.accent
        dim: root.dim
        dimmer: root.dimmer
        fontFamily: root.fontFamily
        busy: root.busyMedia
        surfaceActive: root.surfaceActive
        activePlaybackId: root.activePlaybackId
        sharedAudio: root.sharedAudio
        audioRate: root.audioRate
        onAudioRateRequested: function(rate) { root.audioRateRequested(rate) }
        onPlaybackRequested: function(messageId) {
          root.playbackRequested(messageId)
        }
        onOpenRequested: function(path) { root.openMediaRequested(path) }
        onDownloadRequested: root.downloadMediaRequested()
      }

      TextEdit {
        id: messageText
        objectName: "messageText"
        visible: root.bodyText.length > 0 && root.contactCards.length === 0
        width: parent.width
        height: contentHeight
        text: root.richBody ? root.bodyHtml : root.bodyText
        leftPadding: root.visualMedia ? Style.space(6) : 0
        rightPadding: root.visualMedia ? Style.space(6) : 0
        color: root.foreground
        wrapMode: Text.Wrap
        textFormat: root.richBody ? TextEdit.RichText : TextEdit.PlainText
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
            // Rich text selects with Unicode line separators.
            var value = String(messageText.selectedText || "").replace(/[\u2028\u2029]/g, "\n")
            if (value !== "") root.copyRequested(value)
          }
        }
      }

      // Links open from chips under the text: the body stays plain text, so
      // no markup is ever rendered from a message.
      Flow {
        objectName: "messageLinks"
        visible: root.links.length > 0
        width: parent.width
        spacing: Style.space(6)
        Repeater {
          model: root.links
          delegate: Rectangle {
            required property var modelData
            objectName: "messageLink"
            width: Math.min(linkLabel.implicitWidth + Style.space(30), parent ? parent.width : 400)
            height: Style.space(26)
            radius: Style.cornerRadius
            color: linkHover.hovered ? Style.hoverFillFor(root.foreground, root.accent)
              : Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.10)
            Text {
              textFormat: Text.PlainText
              anchors.left: parent.left
              anchors.leftMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              text: "󰌹"
              color: root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            Text {
              textFormat: Text.PlainText
              id: linkLabel
              anchors.left: parent.left
              anchors.leftMargin: Style.space(24)
              anchors.right: parent.right
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              elide: Text.ElideMiddle
              text: modelData.label
              color: root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            HoverHandler { id: linkHover; cursorShape: Qt.PointingHandCursor }
            Ui.PanelToolTip { visible: linkHover.hovered; text: "Open " + modelData.url }
            TapHandler { onTapped: Qt.openUrlExternally(modelData.url) }
          }
        }
      }

      Repeater {
        model: root.contactCards
        delegate: Rectangle {
          id: contactCard
          required property var modelData
          objectName: "contactCard"
          width: bubbleColumn.width
          height: contactColumn.implicitHeight + Style.space(20)
          radius: Style.space(9)
          color: Qt.rgba(root.background.r, root.background.g, root.background.b, 0.38)
          Column {
            id: contactColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Style.space(10)
            spacing: Style.space(8)
            Row {
              spacing: Style.space(10)
              // Initials in the person's own color, as in the chat list.
              Rectangle {
                objectName: "contactInitials"
                width: Style.space(40)
                height: width
                radius: width / 2
                color: root.senderColor(contactCard.modelData.phone || contactCard.modelData.name)
                Text {
                  textFormat: Text.PlainText
                  anchors.centerIn: parent
                  text: String(contactCard.modelData.name || "?").split(/\s+/).filter(function(part) {
                    return part !== "" }).slice(0, 2).map(function(part) {
                    return part.charAt(0).toUpperCase() }).join("")
                  color: root.background
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.weight: Font.Bold
                }
              }
              Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)
                Text {
                  textFormat: Text.PlainText
                  objectName: "contactName"
                  width: contactColumn.width - Style.space(46)
                  text: String(contactCard.modelData.name || "Contact")
                  color: root.foreground
                  elide: Text.ElideRight
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }
                Text {
                  textFormat: Text.PlainText
                  objectName: "contactPhone"
                  visible: text !== ""
                  text: String(contactCard.modelData.phone || "")
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }
            Row {
              id: contactActions
              width: contactColumn.width
              spacing: Style.space(6)
              visible: String(contactCard.modelData.digits || "") !== ""
              Repeater {
                model: [{ id: "message", label: "Message" }, { id: "copy", label: "Copy number" }]
                delegate: Rectangle {
                  required property var modelData
                  objectName: "contactAction-" + modelData.id
                  width: (contactActions.width - contactActions.spacing) / 2
                  height: Style.space(32)
                  radius: Style.space(8)
                  color: actionHover.hovered ? Style.hoverFillFor(root.foreground, root.accent)
                    : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.07)
                  Text {
                    textFormat: Text.PlainText
                    id: actionLabel
                    anchors.centerIn: parent
                    text: modelData.label
                    color: modelData.id === "message" ? root.accent : root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                  HoverHandler { id: actionHover; cursorShape: Qt.PointingHandCursor }
                  TapHandler {
                    onTapped: modelData.id === "message"
                      ? root.contactChatRequested(contactCard.modelData)
                      : root.copyRequested(String(contactCard.modelData.phone || ""))
                  }
                }
              }
            }
          }
        }
      }

      Text {
        textFormat: Text.PlainText
        objectName: "messageRevoked"
        visible: root.revoked
        width: parent.width
        text: "󰜺  " + (root.message.from_me ? "You deleted this message" : "This message was deleted")
        color: root.dimmer
        wrapMode: Text.Wrap
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.italic: true
      }

      Column {
        objectName: "messagePoll"
        visible: root.poll !== null
        width: parent.width
        spacing: Style.space(6)
        Text {
          textFormat: Text.PlainText
          width: parent.width
          text: root.poll ? String(root.poll.question || "") : ""
          color: root.foreground
          wrapMode: Text.Wrap
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
        }
        Text {
          textFormat: Text.PlainText
          text: root.poll && Number(root.poll.selectable || 1) > 1
            ? "Select one or more" : "Select one"
          color: root.dimmer
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
        Repeater {
          model: root.pollOptions
          delegate: Rectangle {
            id: pollOptionRow
            required property var modelData
            objectName: "pollOption"
            readonly property int votes: Number(modelData.votes || 0)
            readonly property var voterNames: root.listOf(modelData.voters)
            width: parent.width
            height: optionColumn.implicitHeight + Style.space(12)
            radius: Style.space(8)
            color: pollHover.hovered ? Style.hoverFillFor(root.foreground, root.accent)
              : Qt.rgba(root.background.r, root.background.g, root.background.b, 0.45)
            Column {
              id: optionColumn
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(8)
              anchors.rightMargin: Style.space(8)
              spacing: Style.space(4)
              Item {
                width: parent.width
                height: optionText.implicitHeight
                Text {
                  textFormat: Text.PlainText
                  id: optionMark
                  anchors.left: parent.left
                  text: modelData.mine === true
                    ? (root.poll && Number(root.poll.selectable || 1) > 1 ? "󰄲" : "󰄴")
                    : (root.poll && Number(root.poll.selectable || 1) > 1 ? "󰄱" : "󰄰")
                  color: modelData.mine === true ? root.accent : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
                Text {
                  textFormat: Text.PlainText
                  id: optionText
                  anchors.left: optionMark.right
                  anchors.leftMargin: Style.space(8)
                  anchors.right: optionCount.left
                  anchors.rightMargin: Style.space(8)
                  text: String(modelData.text || "")
                  color: root.foreground
                  wrapMode: Text.Wrap
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }
                Text {
                  textFormat: Text.PlainText
                  id: optionCount
                  anchors.right: parent.right
                  text: String(pollOptionRow.votes)
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
              Rectangle {
                width: parent.width
                height: Style.space(4)
                radius: height / 2
                color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
                Rectangle {
                  width: root.pollMostVotes > 0
                    ? parent.width * pollOptionRow.votes / root.pollMostVotes : 0
                  height: parent.height
                  radius: height / 2
                  color: root.accent
                }
              }
              Text {
                textFormat: Text.PlainText
                visible: pollOptionRow.voterNames.length > 0
                width: parent.width
                text: pollOptionRow.voterNames.join(", ")
                color: root.dimmer
                elide: Text.ElideRight
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
            HoverHandler { id: pollHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.votePollOption(modelData.text) }
          }
        }
        Text {
          textFormat: Text.PlainText
          text: {
            var count = root.poll ? Number(root.poll.voters || 0) : 0
            return count === 1 ? "1 vote" : count + " votes"
          }
          color: root.dimmer
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      Column {
        visible: root.buttonItems.length > 0
        width: parent.width
        spacing: Style.space(4)
        Repeater {
          model: root.buttonItems
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

    }

    // Time and marks; under a sticker they sit in a small pill, as on
    // the phone, instead of floating on their own.
    Item {
      id: messageMeta
      objectName: "messageMeta"
      anchors.right: parent.right
      anchors.rightMargin: root.sticker ? 0 : root.metaOverMedia ? Style.space(10) : Style.space(10)
      anchors.bottom: parent.bottom
      anchors.bottomMargin: root.sticker ? 0 : root.metaOverMedia ? Style.space(10)
        : root.metaInAudio ? Style.space(14) : Style.space(6)
      readonly property bool pill: root.sticker || root.metaOverMedia
      width: metaRow.implicitWidth + (pill ? Style.space(14) : 0)
      height: metaRow.implicitHeight + (pill ? Style.space(6) : 0)
      Rectangle {
        objectName: "stickerTimePill"
        visible: root.sticker
        anchors.fill: parent
        radius: height / 2
        color: Qt.tint(root.background, Qt.rgba(root.foreground.r, root.foreground.g,
          root.foreground.b, 0.12))
      }
      // Over a photo the time sits on a dark pill, readable on any picture.
      Rectangle {
        objectName: "mediaTimePill"
        visible: root.metaOverMedia
        anchors.fill: parent
        radius: height / 2
        color: Qt.rgba(0, 0, 0, 0.5)
      }
    Row {
      id: metaRow
      anchors.centerIn: parent
      spacing: Style.space(6)
      Text {
        textFormat: Text.PlainText
        visible: root.message.edited === true
        text: "edited"
        color: root.metaColor
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.italic: true
      }
      Text {
        textFormat: Text.PlainText
        visible: root.message.starred === true
        text: "󰓎"
        color: root.metaColor
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
      // A message still on its way from here shows a clock until the stored
      // row replaces it, or an alert when it could not be sent.
      Text {
        textFormat: Text.PlainText
        objectName: "messagePending"
        visible: root.pending
        text: root.sendFailed ? "󰀦" : "󰅐"
        color: root.sendFailed ? Color.urgent : root.metaColor
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        HoverHandler { id: pendingHover }
        Ui.PanelToolTip {
          visible: pendingHover.hovered
          text: root.sendFailed ? "Not sent · right-click to try again"
            : root.message.send_state === "sent" ? "Sent · saving it on this computer"
            : root.message.send_state === "queued" ? "Waiting for the message before it…"
            : "Sending…"
        }
      }
      Text {
        textFormat: Text.PlainText
        objectName: "messageTimestamp"
        text: root.timestampText
        color: root.metaColor
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        HoverHandler { id: timestampHover }
        Ui.PanelToolTip { visible: timestampHover.hovered; text: root.fullTimestampText }
      }
      // Ticks only for a state wacli recorded: a guess would be a claim the
      // data cannot back.
      Text {
        textFormat: Text.PlainText
        objectName: "messageTicks"
        visible: root.showsTicks
        text: root.deliveryStatus === "sent" ? "󰄬"
          : root.deliveryStatus === "pending" ? "󰅐"
          : root.deliveryStatus === "error" ? "󰀦" : "󰄭"
        color: root.deliveryStatus === "read" || root.deliveryStatus === "played" ? root.accent
          : root.deliveryStatus === "error" ? Color.urgent : root.metaColor
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        HoverHandler { id: ticksHover }
        Ui.PanelToolTip {
          visible: ticksHover.hovered
          text: root.deliveryStatus === "sent" ? "Sent"
            : root.deliveryStatus === "delivered" ? (root.groupChat ? "Delivered to everyone" : "Delivered")
            : root.deliveryStatus === "read" ? (root.groupChat ? "Read by everyone" : "Read")
            : root.deliveryStatus === "played" ? (root.groupChat ? "Played by everyone" : "Played")
            : root.deliveryStatus === "pending" ? "Waiting to go out from your phone"
            : "Your phone could not send it"
        }
      }
    }
    }

    Rectangle {
      id: actionSurface
      objectName: "messageActions"
      z: 5
      // Beside the bubble (incoming: right, outgoing: left) whenever the row
      // has room, in the dropdown too, so the actions never cover the text.
      // A bubble as wide as the row gets them straddling its top edge, where
      // they cover only the padding.
      readonly property bool outside: root.width - bubble.width >= width + Style.space(16)
      visible: !root.pending && !root.revoked
        && (rowHover.hovered || reactionPicker.opened || actionMenu.opened)
      // Positioned explicitly: conditional anchors keep the previous edge when
      // `outside` flips, which pinned both sides to the bubble's right edge.
      x: outside
        ? (root.message.from_me ? -width - Style.space(6) : parent.width + Style.space(6))
        : (root.message.from_me ? Style.space(5) : parent.width - width - Style.space(5))
      y: outside ? 0 : -Math.round(height / 2)
      width: actionRow.implicitWidth + Style.space(6)
      height: actionRow.implicitHeight + Style.space(4)
      radius: height / 2
      // Opaque: the theme's normal fill is about 4% alpha, so inside the
      // bubble (the dropdown's layout) the message text showed through and
      // the buttons looked buried under it.
      color: Qt.tint(root.background, Qt.rgba(root.foreground.r, root.foreground.g,
        root.foreground.b, 0.12))
      border.width: 1
      border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)

      Row {
        id: actionRow
        anchors.centerIn: parent
        spacing: Style.space(1)
        Repeater {
          model: [
            { icon: "󰑚", action: "reply", hint: "Reply" },
            { icon: "󰇵", action: "react", hint: "React" },
            { icon: "󰇙", action: "more", hint: "More actions" }
          ]
          delegate: Ui.PanelActionButton {
            required property var modelData
            objectName: "messageAction-" + modelData.action
            iconText: modelData.icon
            tooltipText: modelData.hint
            foreground: root.dim
            hoverColor: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            size: Style.space(24)
            onClicked: {
              root.selectedRequested()
              if (modelData.action === "reply") root.replyRequested()
              else if (modelData.action === "react") reactionPicker.open()
              else { root.menuAtPointer = false; actionMenu.open() }
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

    TapHandler {
      acceptedButtons: Qt.RightButton
      onTapped: function(eventPoint) {
        root.openContextMenu(eventPoint.position.x, eventPoint.position.y)
      }
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
      objectName: "messageActionMenu"
      x: root.menuAtPointer
        ? Math.max(-bubble.x, Math.min(root.width - bubble.x - width, root.menuPoint.x))
        : Math.max(0, bubble.width - width)
      y: root.menuAtPointer
        ? root.menuPoint.y
        : actionSurface.y + actionSurface.height + Style.space(3)
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
          model: root.menuActions
          delegate: Rectangle {
            required property var modelData
            objectName: "messageMenu-" + modelData.action
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
            TapHandler { onTapped: root.runMenuAction(modelData.action) }
          }
        }
      }
    }
  }

  ChatAvatar {
    objectName: "messageSenderAvatar"
    visible: root.senderGutter && !root.joinsBelow
    x: 0
    anchors.bottom: bubble.bottom
    width: Style.space(30)
    height: width
    showPhoto: root.senderAvatarPath !== ""
    chat: ({ name: String(root.message.sender || ""), kind: "dm",
      jid: String(root.message.sender_jid || root.message.sender || ""),
      avatar_path: root.senderAvatarPath })
    foreground: root.foreground
    background: root.background
    accent: root.accent
    fontFamily: root.fontFamily
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
