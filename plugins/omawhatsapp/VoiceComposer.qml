import QtQuick
import qs.Commons
import "AccountModel.js" as AccountModel
import "VoiceRecorderModel.js" as VoiceModel

Item {
  id: root

  property var service: null
  property string account: ""
  property string jid: ""
  property bool offline: false
  property color foreground: Color.foreground
  property color background: Color.background
  property color accent: Color.accent
  property color urgent: Color.urgent
  property color muted: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.62)
  property string fontFamily: Style.font.family
  property bool compact: false
  property string demoState: "idle"
  property string demoAccount: ""
  property string demoJid: ""
  property int demoDurationMs: 0
  property int demoPositionMs: 0
  property bool demoPlaying: false

  readonly property string state: service
    ? String(service.voiceState || "idle") : String(demoState || "idle")
  readonly property string draftJid: service
    ? String(service.voiceDraftJid || "") : String(demoJid || "")
  readonly property string draftAccount: service
    ? String(service.voiceDraftAccount || "") : String(demoAccount || "")
  readonly property bool forThisChat:
    AccountModel.chatKey(draftAccount, draftJid) === AccountModel.chatKey(account, jid)
    && VoiceModel.hasDraft(state)
  readonly property int elapsed: service
    ? Number(service.voiceDurationMs || 0) : Number(demoDurationMs || 0)
  readonly property int previewPosition: service
    ? Number(service.voicePlaybackPosition || 0) : Number(demoPositionMs || 0)
  readonly property bool playing: service ? service.voicePlaying === true : demoPlaying

  visible: forThisChat
  implicitHeight: Style.space(compact ? 42 : 54)

  component RoundAction: Rectangle {
    id: action
    property string glyph: ""
    property string tooltip: ""
    property bool filled: false
    signal activated()
    width: Style.space(root.compact ? 30 : 36)
    height: width
    radius: width / 2
    color: !enabled ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
      : filled ? root.accent
      : actionHover.hovered ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18)
      : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
    opacity: enabled ? 1 : 0.48
    Text {
      textFormat: Text.PlainText
      anchors.centerIn: parent
      text: action.glyph
      color: action.filled ? root.background : root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      font.weight: Font.DemiBold
    }
    HoverHandler { id: actionHover }
    TapHandler { enabled: action.enabled; onTapped: action.activated() }
  }

  Row {
    anchors.fill: parent
    spacing: Style.space(root.compact ? 6 : 9)

    RoundAction {
      anchors.verticalCenter: parent.verticalCenter
      glyph: "×"
      tooltip: "Discard voice draft"
      enabled: root.state !== "sending" && root.state !== "discarding"
      onActivated: if (root.service) root.service.discardVoice()
    }

    RoundAction {
      anchors.verticalCenter: parent.verticalCenter
      visible: root.state === "review"
      glyph: root.playing ? "Ⅱ" : "▶"
      tooltip: root.playing ? "Pause preview" : "Preview voice note"
      onActivated: if (root.service) root.service.toggleVoicePlayback()
    }

    Rectangle {
      visible: root.state === "recording"
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(9)
      height: width
      radius: width / 2
      color: root.urgent
      SequentialAnimation on opacity {
        running: root.state === "recording"
        loops: Animation.Infinite
        NumberAnimation { to: 0.35; duration: 650; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1; duration: 650; easing.type: Easing.InOutSine }
      }
    }

    Column {
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(0, parent.width - Style.space(root.compact ? 116 : 144))
      spacing: Style.space(3)
      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: VoiceModel.stateLabel(root.state, root.offline)
        color: root.state === "recording" ? root.urgent : root.foreground
        elide: Text.ElideRight
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.weight: Font.DemiBold
      }
      Rectangle {
        visible: root.state === "review"
        width: parent.width
        height: 3
        radius: height / 2
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
        Rectangle {
          width: parent.width * VoiceModel.progress(root.previewPosition, root.elapsed)
          height: parent.height
          radius: height / 2
          color: root.accent
        }
      }
      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: VoiceModel.elapsedLabel(root.state === "review" && root.previewPosition > 0
          ? root.previewPosition : root.elapsed)
          + (root.state === "review" ? "  ·  preview before sending" : "")
        color: root.muted
        elide: Text.ElideRight
        font.family: root.fontFamily
        font.pixelSize: Math.max(9, Style.font.caption - 1)
      }
    }

    RoundAction {
      anchors.verticalCenter: parent.verticalCenter
      visible: root.state === "recording"
      glyph: "■"
      tooltip: "Stop and review"
      filled: true
      onActivated: if (root.service) root.service.stopVoiceRecording()
    }

    RoundAction {
      anchors.verticalCenter: parent.verticalCenter
      visible: root.state === "review"
      glyph: root.offline ? "⌁" : "➤"
      tooltip: root.offline ? "Go online to send" : "Send voice note"
      filled: !root.offline
      enabled: !root.offline
      onActivated: if (root.service) root.service.sendVoiceDraft()
    }

    Text {
      textFormat: Text.PlainText
      visible: root.state === "preparing" || root.state === "finalizing"
        || root.state === "sending" || root.state === "discarding"
      anchors.verticalCenter: parent.verticalCenter
      text: "…"
      color: root.accent
      font.family: root.fontFamily
      font.pixelSize: Style.font.heading
    }
  }
}
