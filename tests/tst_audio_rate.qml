import QtQuick
import QtTest
import "../plugins/omawhatsapp" as Oma

// Voice notes play at 1×, 1.5× or 2×, one choice shared by every bubble, and
// show elapsed and total time.
TestCase {
  id: testCase
  name: "AudioRate"
  width: 500
  height: 200
  visible: true
  when: windowShown

  Component {
    id: bubbleComponent
    Oma.MediaBubble {
      width: 420
      message: ({ id: "voice", media_type: "audio", mime_type: "audio/ogg; codecs=opus",
        local_path: "/nonexistent/synthetic-voice.ogg", text: "" })
      foreground: "#eeeeee"; background: "#111111"; accent: "#66ccaa"
      dim: "#999999"; dimmer: "#777777"; fontFamily: "monospace"
    }
  }

  Component { id: spyComponent; SignalSpy {} }

  function test_the_speed_chip_cycles_through_the_three_speeds() {
    var bubble = createTemporaryObject(bubbleComponent, testCase)
    verify(bubble.audio)
    compare(bubble.nextAudioRate(1), 1.5)
    compare(bubble.nextAudioRate(1.5), 2)
    compare(bubble.nextAudioRate(2), 1)
    var chip = findChild(bubble, "audioRate")
    verify(chip !== null)
    var spy = createTemporaryObject(spyComponent, testCase, { target: bubble, signalName: "audioRateRequested" })
    tryVerify(function() { return chip.width > 0 }, 2000)
    mouseClick(chip, chip.width / 2, chip.height / 2)
    compare(spy.count, 1)
    compare(spy.signalArguments[0][0], 1.5)
    bubble.audioRate = 2
    compare(findChild(bubble, "audioMediaPlayer").playbackRate, 2, "the player follows the shared speed")
  }

  function test_times_read_like_a_clock() {
    var bubble = createTemporaryObject(bubbleComponent, testCase)
    compare(bubble.clockText(0), "0:00")
    compare(bubble.clockText(9500), "0:09")
    compare(bubble.clockText(75000), "1:15")
  }
}
