import QtQuick
import QtTest
import "../plugins/omawhatsapp" as Oma

// Messages the owner saw correctly on the phone and wrongly here: reactions,
// polls and their votes, locations, and messages deleted for everyone. Each
// goes through a ListView, as in the app, because that is where lists inside
// a message stop being JavaScript arrays.
TestCase {
  id: testCase
  name: "MessageKinds"
  width: 700
  height: 900
  visible: true
  when: windowShown

  Component { id: spyComponent; SignalSpy {} }

  Component {
    id: listComponent
    ListView {
      id: list
      width: 640
      height: 800
      property var rows: []
      model: rows
      delegate: Oma.MessageBubble {
        required property var modelData
        width: list.width
        message: modelData
        foreground: "#eeeeee"; background: "#111111"; accent: "#66ccaa"
        dim: "#999999"; dimmer: "#777777"; fontFamily: "monospace"
      }
    }
  }

  function bubbleFor(message) {
    var list = createTemporaryObject(listComponent, testCase, {
      rows: JSON.parse(JSON.stringify([message])) })
    tryVerify(function() { return list.count === 1 && list.itemAtIndex(0) !== null })
    return list.itemAtIndex(0)
  }

  function base(fields) {
    return Object.assign({ id: "m1", text: "", sender: "You", timestamp: 1790280000,
      from_me: true, media_type: "", reactions: [] }, fields)
  }

  function test_a_reaction_shows_under_the_bubble() {
    var bubble = bubbleFor(base({ text: "hello",
      reactions: [{ emoji: "👍", from_me: true, sender: "You" },
                  { emoji: "👍", from_me: false, sender: "Sam" }] }))
    compare(bubble.reactionPills.length, 1, "the list model's sequence still counts")
    compare(bubble.reactionPills[0].count, 2)
    verify(bubble.reactionPills[0].mine)
  }

  function test_interactive_buttons_show_through_the_list_model() {
    var bubble = bubbleFor(base({ from_me: false, text: "Pick one",
      buttons: [{ display_text: "Yes" }, { display_text: "No" }] }))
    compare(bubble.buttonItems.length, 2)
  }

  function test_a_deleted_message_is_a_placeholder_without_actions() {
    var mine = bubbleFor(base({ revoked: true }))
    var label = findChild(mine, "messageRevoked")
    verify(label.visible)
    compare(label.text, "󰜺  You deleted this message")
    compare(mine.menuActions.map(function(item) { return item.action }), ["delete-me"])
    var theirs = bubbleFor(base({ revoked: true, from_me: false, sender: "Sam" }))
    compare(findChild(theirs, "messageRevoked").text, "󰜺  This message was deleted")
  }

  function test_a_poll_shows_options_votes_and_who_voted() {
    var bubble = bubbleFor(base({ poll: { question: "Which day?", selectable: 1, voters: 3,
      options: [{ text: "Monday", votes: 2, voters: ["You", "Sam"], mine: true },
                { text: "Tuesday", votes: 1, voters: ["Alex"], mine: false }] } }))
    verify(findChild(bubble, "messagePoll").visible)
    compare(bubble.pollOptions.length, 2)
    compare(bubble.pollMostVotes, 2)
    var spy = createTemporaryObject(spyComponent, testCase,
      { target: bubble, signalName: "pollVoteRequested" })
    verify(bubble.votePollOption("Tuesday"))
    compare(spy.count, 1)
    compare(spy.signalArguments[0][0], ["Tuesday"])
    verify(!bubble.votePollOption("Monday"), "your current single choice is already sent")
  }

  function test_a_multiple_choice_poll_adds_and_drops_choices() {
    var bubble = bubbleFor(base({ poll: { question: "Snacks?", selectable: 2, voters: 1,
      options: [{ text: "Tea", votes: 1, voters: ["You"], mine: true },
                { text: "Cake", votes: 0, voters: [], mine: false },
                { text: "Fruit", votes: 0, voters: [], mine: false }] } }))
    var spy = createTemporaryObject(spyComponent, testCase,
      { target: bubble, signalName: "pollVoteRequested" })
    verify(bubble.votePollOption("Cake"))
    compare(spy.signalArguments[0][0], ["Tea", "Cake"])
    verify(!bubble.votePollOption("Tea"), "WhatsApp keeps at least one choice")
  }

  function test_a_location_shows_its_place_and_opens_the_map() {
    var bubble = bubbleFor(base({ media_type: "location", latitude: -21.7946,
      longitude: -48.1756, location_name: "Construction site", location_address: "Main street, 1" }))
    var card = null
    tryVerify(function() { card = findChild(bubble, "locationCard"); return card !== null })
    compare(findChild(card, "locationName").text, "Construction site")
    verify(findChild(card, "locationCoordinates").text.indexOf("-21.79460, -48.17560") === 0)
    compare(card.mapUrl, "https://www.openstreetmap.org/?mlat=-21.794600&mlon=-48.175600#map=17/-21.794600/-48.175600")
    var unnamed = bubbleFor(base({ id: "m2", media_type: "location", latitude: 1, longitude: 2 }))
    var other = null
    tryVerify(function() { other = findChild(unnamed, "locationCard"); return other !== null })
    compare(findChild(other, "locationName").text, "Location")
  }
}
