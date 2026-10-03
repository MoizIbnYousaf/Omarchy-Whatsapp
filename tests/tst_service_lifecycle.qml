import QtQuick
import QtTest
import "../plugins/omawhatsapp" as Oma

// L233/L234: Quit stops receiving until OmaWhatsApp opens again; starting
// with the system is a setting of its own.
TestCase {
  id: testCase
  name: "ServiceLifecycle"

  Component { id: serviceComponent; Oma.Service {} }

  function finish(service, payload) {
    var process = findChild(service, "controlProcess")
    process.stdout.text = JSON.stringify(payload)
    process.running = false
    process.exited(0)
  }

  function test_quit_and_launch_go_through_the_helper() {
    var service = createTemporaryObject(serviceComponent, testCase)
    service.ready = true
    service.syncActive = true
    service.presenceSupported = true
    service.showOnline = true
    verify(service.quitApp())
    var process = findChild(service, "controlProcess")
    compare(process.command[process.command.length - 1], "quit")
    finish(service, { ok: true, kind: "quit", closed: true })
    verify(service.closed)
    verify(!service.syncActive)
    verify(!service.presenceActive, "not shown online while closed")
    compare(service.barTooltip, "OmaWhatsApp is closed · click to open")
    verify(service.launchApp())
    compare(process.command[process.command.length - 1], "launch")
    finish(service, { ok: true, kind: "launch", closed: false })
    verify(!service.closed)
    verify(service.syncActive)
  }
}
