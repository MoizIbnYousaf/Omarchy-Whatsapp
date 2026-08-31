import QtQuick
import QtTest
import "../plugins/omawhatsapp" as Oma

TestCase {
  id: testCase
  name: "AppMediaLifecycle"

  Component {
    id: appComponent
    Oma.App {
      width: 1000
      height: 700
    }
  }

  function test_full_viewer_suspends_the_mounted_timeline() {
    var app = createTemporaryObject(appComponent, testCase)
    verify(app !== null)
    app.open('{"demo":true}')
    tryCompare(app, "timelineMediaActive", true)

    app.openMedia("__demo__")
    tryCompare(app, "timelineMediaActive", false)

    app.open('{"demo":true}')
    tryCompare(app, "timelineMediaActive", true)
    app.close()
    compare(app.timelineMediaActive, false)
  }
}
