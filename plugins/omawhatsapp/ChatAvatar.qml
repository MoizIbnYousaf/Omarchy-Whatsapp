import QtQuick
import QtQuick.Effects
import "Tint.js" as Tint

Item {
  id: root

  required property var chat
  required property color foreground
  required property color background
  required property color accent
  required property string fontFamily
  property bool selected: false
  // Settings → Chats → Chat photos; off shows initials or the group icon.
  property bool showPhoto: true

  readonly property string localPath: showPhoto ? String(chat && chat.avatar_path || "") : ""
  readonly property bool localAvatar: localPath.charAt(0) === "/"
    || localPath === "__demo_avatar__"
  readonly property url avatarSource: localPath === "__demo_avatar__"
    ? Qt.resolvedUrl("assets/demo-photo.png")
    : (localAvatar ? encodedFileUrl(localPath) : "")
  readonly property bool avatarReady: localAvatar
    && avatarImage.status === Image.Ready

  implicitWidth: 38
  implicitHeight: implicitWidth

  // People are round and groups a rounded square, so the two read apart
  // before the name does; without a photo each has its own color.
  readonly property bool group: String(chat && chat.kind || "") === "group"
  readonly property real shapeRadius: group ? Math.round(width * 0.29) : width / 2
  readonly property color tint: Tint.personColor(
    String(chat && (chat.jid || chat.name) || ""), accent)

  function encodedFileUrl(path) {
    return "file://" + String(path || "").split("/")
      .map(function(part) { return encodeURIComponent(part) }).join("/")
  }

  function fallbackLabel() {
    if (root.group && String(chat && chat.name || "").trim() === "") return "󰠮"
    // Someone known only by number: a person glyph, not the "+" of the number.
    if (/^[+]?[0-9 ().-]+$/.test(String(chat && chat.name || "").trim())) return "󰀓"
    var parts = String(chat && chat.name || "?").trim().split(/\s+/)
      .filter(function(part) { return part !== "" })
    if (parts.length === 0) return "?"
    if (parts.length === 1) return parts[0].slice(0, 1).toUpperCase()
    return (parts[0].slice(0, 1) + parts[parts.length - 1].slice(0, 1)).toUpperCase()
  }

  Rectangle {
    objectName: "chatAvatarBackdrop"
    anchors.fill: parent
    radius: root.shapeRadius
    color: root.avatarReady ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.12)
      : root.tint
  }

  Rectangle {
    id: avatarMask
    anchors.fill: parent
    radius: root.shapeRadius
    visible: false
    layer.enabled: true
  }

  Item {
    anchors.fill: parent
    visible: root.localAvatar
    layer.enabled: true
    layer.smooth: true
    layer.effect: MultiEffect {
      maskEnabled: true
      maskSource: avatarMask
      maskThresholdMin: 0.3
      maskSpreadAtMin: 0.3
    }

    Image {
      id: avatarImage
      objectName: "chatAvatarImage"
      anchors.fill: parent
      source: root.avatarSource
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      cache: true
      smooth: true
    }
  }

  Text {
    textFormat: Text.PlainText
    objectName: "chatAvatarFallback"
    visible: !root.avatarReady
    anchors.centerIn: parent
    text: root.fallbackLabel()
    color: root.background
    font.family: root.fontFamily
    font.pixelSize: text === "󰠮" ? Math.round(root.width * 0.47)
      : Math.max(9, Math.round(root.width * 0.33))
    font.weight: Font.Bold
  }
}
