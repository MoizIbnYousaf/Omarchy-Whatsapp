import QtQuick
import QtQuick.Effects

Item {
  id: root

  required property var chat
  required property color foreground
  required property color background
  required property color accent
  required property string fontFamily
  property bool selected: false

  readonly property string localPath: String(chat && chat.avatar_path || "")
  readonly property bool localAvatar: localPath.charAt(0) === "/"
    || localPath === "__demo_avatar__"
  readonly property url avatarSource: localPath === "__demo_avatar__"
    ? Qt.resolvedUrl("assets/demo-photo.png")
    : (localAvatar ? encodedFileUrl(localPath) : "")
  readonly property bool avatarReady: localAvatar
    && avatarImage.status === Image.Ready

  implicitWidth: 38
  implicitHeight: implicitWidth

  function encodedFileUrl(path) {
    return "file://" + String(path || "").split("/")
      .map(function(part) { return encodeURIComponent(part) }).join("/")
  }

  function fallbackLabel() {
    if (chat && chat.kind === "group") return "󰠮"
    var parts = String(chat && chat.name || "?").trim().split(/\s+/)
      .filter(function(part) { return part !== "" })
    if (parts.length === 0) return "?"
    if (parts.length === 1) return parts[0].slice(0, 1).toUpperCase()
    return (parts[0].slice(0, 1) + parts[parts.length - 1].slice(0, 1)).toUpperCase()
  }

  Rectangle {
    anchors.fill: parent
    radius: width / 2
    color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b,
      root.selected ? 0.22 : 0.12)
  }

  Rectangle {
    id: avatarMask
    anchors.fill: parent
    radius: width / 2
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
    color: root.accent
    font.family: root.fontFamily
    font.pixelSize: chat && chat.kind === "group" ? 18 : 13
    font.weight: Font.DemiBold
  }
}
