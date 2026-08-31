import QtQuick
import QtTest
import "../plugins/omawhatsapp" as Oma

TestCase {
  id: testCase
  name: "AcknowledgementQueue"

  Component {
    id: queueComponent
    Oma.AcknowledgementQueue { helper: "/synthetic/omawhatsapp" }
  }

  function processFor(queue) {
    return findChild(queue, "notificationAcknowledgeProcess")
  }

  function complete(process, ok, message) {
    var output = findChild(process, "notificationAcknowledgeOutput")
    var error = findChild(process, "notificationAcknowledgeError")
    verify(output !== null)
    verify(error !== null)
    output.text = ok ? '{"ok":true}' : ""
    error.text = ok ? "" : String(message || "synthetic failure")
    process.running = false
    process.exited(ok ? 0 : 1)
    wait(0)
  }

  function test_rapid_account_scoped_requests_drain_in_order() {
    var queue = createTemporaryObject(queueComponent, testCase)
    verify(queue !== null)
    var process = processFor(queue)
    verify(process !== null)
    var completed = []
    queue.completed.connect(function(ref) { completed.push(ref.key) })

    verify(queue.enqueue("work", "shared@s.whatsapp.net"))
    compare(process.running, true)
    compare(queue.currentRef.key, "work\nshared@s.whatsapp.net")
    verify(queue.enqueue("home", "shared@s.whatsapp.net"))
    compare(queue.pendingRefs.length, 1)

    process.started()
    complete(process, true)
    compare(queue.currentRef.key, "home\nshared@s.whatsapp.net")
    compare(process.running, true)
    process.started()
    complete(process, true)

    compare(completed, ["work\nshared@s.whatsapp.net",
      "home\nshared@s.whatsapp.net"])
    compare(queue.pendingRefs.length, 0)
    compare(queue.currentRef.key, "")
  }

  function test_queued_aggregate_subsumes_exact_requests_without_interrupting_work() {
    var queue = createTemporaryObject(queueComponent, testCase)
    verify(queue !== null)
    var process = processFor(queue)
    verify(process !== null)

    verify(queue.enqueue("work", "one@s.whatsapp.net"))
    verify(queue.enqueue("home", "two@s.whatsapp.net"))
    verify(queue.enqueue("", ""))
    compare(queue.enqueue("", ""), false)
    compare(queue.currentRef.key, "work\none@s.whatsapp.net")
    compare(queue.pendingRefs.length, 1)
    compare(queue.pendingRefs[0].account, "")
    compare(queue.pendingRefs[0].jid, "")
    compare(queue.enqueue("home", "three@s.whatsapp.net"), false)

    process.started()
    complete(process, true)
    compare(queue.currentRef.account, "")
    compare(queue.currentRef.jid, "")
    compare(process.running, true)
    compare(queue.enqueue("", ""), false)
    process.started()
    complete(process, true)
    compare(queue.currentRef.key, "")
  }

  function test_failure_does_not_stall_the_queue() {
    var queue = createTemporaryObject(queueComponent, testCase)
    verify(queue !== null)
    var process = processFor(queue)
    var failures = []
    queue.failed.connect(function(message, ref) {
      failures.push(ref.key + ":" + message)
    })

    verify(queue.enqueue("work", "one@s.whatsapp.net"))
    verify(queue.enqueue("home", "two@s.whatsapp.net"))
    process.started()
    complete(process, false, "synthetic failure")
    compare(failures, ["work\none@s.whatsapp.net:synthetic failure"])
    compare(queue.currentRef.key, "home\ntwo@s.whatsapp.net")
    process.started()
    complete(process, true)
    compare(queue.currentRef.key, "")
  }
}
