import QtQml
import QtQuick
import QtTest
import QtMultimedia
import "../plugins/omawhatsapp" as Oma
import "../plugins/omawhatsapp/MediaModel.js" as MediaModel

TestCase {
  id: testCase
  name: "MediaViewer"
  property string coordinatedPlaybackId: ""

  Component {
    id: viewerComponent
    Oma.MediaViewerModel {}
  }

  Component {
    id: mediaBubbleComponent
    Oma.MediaBubble {
      width: 400
      message: ({
        id: "album-first",
        media_type: "album",
        mime_type: "image/svg+xml",
        local_path: "__demo__",
        album_count: 2,
        album_items: [
          { id: "album-first", media_type: "image", mime_type: "image/svg+xml",
            local_path: "__demo__", album_index: 0 },
          { id: "album-second", media_type: "image", mime_type: "image/svg+xml",
            local_path: "__demo_photo__", album_index: 1 }
        ]
      })
      foreground: "#eeeeee"
      background: "#111111"
      accent: "#66ccaa"
      dim: "#aaaaaa"
      dimmer: "#777777"
      fontFamily: "monospace"
    }
  }

  Component {
    id: genericMediaBubbleComponent
    Oma.MediaBubble {
      width: 400
      foreground: "#eeeeee"
      background: "#111111"
      accent: "#66ccaa"
      dim: "#aaaaaa"
      dimmer: "#777777"
      fontFamily: "monospace"
    }
  }

  Component {
    id: playbackCoordinatorComponent
    Oma.PlaybackCoordinator {}
  }

  Component {
    id: fullViewerComponent
    Oma.MediaViewer {
      width: 900
      height: 600
      foreground: "#eeeeee"
      background: "#111111"
      accent: "#66ccaa"
      dim: "#aaaaaa"
      fontFamily: "monospace"
    }
  }

  function media(id) {
    return {
      id: id,
      sender: "Demo",
      timestamp: 1,
      text: "Synthetic image",
      media_type: "image",
      mime_type: "image/svg+xml",
      local_path: "__demo__"
    }
  }

  function video(localPath) {
    return {
      id: "synthetic-video",
      sender: "Demo",
      timestamp: 1,
      text: "Synthetic video",
      media_type: "video",
      mime_type: "video/mp4",
      local_path: localPath,
      filename: "synthetic.mp4",
      file_size: 1234
    }
  }

  function animatedImage(localPath) {
    return {
      id: "synthetic-animation",
      sender: "Demo",
      timestamp: 1,
      text: "Synthetic animation",
      media_type: "sticker",
      mime_type: "image/svg+xml",
      local_path: localPath
    }
  }

  function stillImage(localPath, mime) {
    return {
      id: "synthetic-still",
      sender: "Demo",
      timestamp: 1,
      text: "Synthetic still",
      media_type: "image",
      mime_type: mime,
      local_path: localPath
    }
  }

  function fixturePath(name) {
    var url = String(Qt.resolvedUrl(".generated-media/" + name))
    return decodeURIComponent(url.slice(7))
  }

  function test_open_navigation_zoom_and_close() {
    var viewer = createTemporaryObject(viewerComponent, testCase)
    verify(viewer !== null)
    viewer.items = [media("one"), media("two"), media("three")]
    viewer.openAt(1)
    compare(viewer.opened, true)
    compare(viewer.currentIndex, 1)
    compare(viewer.currentItem.id, "two")

    viewer.navigate(1)
    compare(viewer.currentItem.id, "three")
    viewer.navigate(1)
    compare(viewer.currentItem.id, "one")
    viewer.navigate(-1)
    compare(viewer.currentItem.id, "three")

    viewer.setZoom(10)
    compare(viewer.zoom, 4)
    viewer.setZoom(0.1)
    compare(viewer.zoom, 0.5)
    viewer.closeViewer()
    compare(viewer.opened, false)
    compare(viewer.currentIndex, -1)
    compare(viewer.zoom, 1)
  }

  function test_open_is_bounded() {
    var viewer = createTemporaryObject(viewerComponent, testCase)
    verify(viewer !== null)
    viewer.items = [media("one"), media("two")]
    viewer.openAt(99)
    compare(viewer.currentIndex, 1)
    viewer.openAt(-10)
    compare(viewer.currentIndex, 0)
  }

  function test_album_accepts_qt_variant_lists_offscreen() {
    var bubble = createTemporaryObject(mediaBubbleComponent, testCase)
    verify(bubble !== null)
    tryCompare(bubble, "album", true)
    compare(bubble.albumItems.length, 2)
    verify(bubble.implicitHeight > 0)
    compare(String(bubble.localUrlFor(bubble.albumItems[1])).indexOf("demo-photo.png") >= 0,
            true)
  }

  function test_video_preview_is_bounded_and_responsive() {
    var bubble = createTemporaryObject(genericMediaBubbleComponent, testCase,
      { message: video("__demo_video__") })
    verify(bubble !== null)
    compare(bubble.mediaKind, "video")
    compare(bubble.previewHeight, 225)
    tryCompare(bubble, "implicitHeight", 225)
    verify(findChild(bubble, "videoMediaSurface") !== null)
    verify(findChild(bubble, "videoPosterOverlay") !== null)
    verify(findChild(bubble, "videoPlaybackControls") !== null)
    compare(findChild(bubble, "videoMediaSurface").active, true)

    bubble.surfaceActive = false
    compare(findChild(bubble, "videoMediaSurface").active, false)

    bubble.width = 1400
    compare(bubble.previewHeight, 315)
    tryCompare(bubble, "implicitHeight", 315)

    var portrait = video("__demo_video__")
    portrait.media_width = 1080
    portrait.media_height = 1920
    bubble.message = portrait
    compare(bubble.previewHeight, 315)
  }

  function test_missing_video_stays_compact_and_downloadable() {
    var bubble = createTemporaryObject(genericMediaBubbleComponent, testCase,
      { message: video("") })
    verify(bubble !== null)
    compare(bubble.mediaKind, "missing")
    tryCompare(bubble, "implicitHeight", 68)
    verify(findChild(bubble, "missingMediaSurface") !== null)
    compare(findChild(bubble, "missingMediaAction").text,
      "Download to preview · 1.2 KB")

    // The same timeline object becomes the native player as soon as the
    // exact-message download refresh publishes its local path.
    bubble.message = video(fixturePath("synthetic.mp4"))
    tryVerify(function() {
      return findChild(bubble, "videoMediaSurface") !== null
    })
    var player = findChild(bubble, "videoMediaSurface")
    tryVerify(function() { return player.duration > 0 && !player.failed }, 5000)
  }

  function test_timeline_animations_are_static_posters() {
    var bubble = createTemporaryObject(genericMediaBubbleComponent, testCase,
      { message: animatedImage("__demo__") })
    verify(bubble !== null)
    var animation = findChild(bubble, "animatedMediaSurface")
    verify(animation !== null)
    compare(animation.playing, false)
    bubble.surfaceActive = false
    compare(animation.playing, false)
    bubble.surfaceActive = true
    compare(animation.playing, false)
  }

  function test_viewer_animation_uses_the_cross_surface_lease() {
    var coordinator = createTemporaryObject(playbackCoordinatorComponent, testCase)
    var viewer = createTemporaryObject(fullViewerComponent, testCase)
    verify(coordinator !== null)
    verify(viewer !== null)
    viewer.playback = coordinator
    viewer.chatRef = { account: "work", jid: "shared@example" }
    viewer.items = [animatedImage(fixturePath("synthetic.gif"))]
    compare(viewer.playback, coordinator)
    viewer.openAt(0)
    compare(viewer.opened, true)
    compare(viewer.animatedImage, true)
    tryVerify(function() {
      return coordinator.owns("app-viewer",
        { account: "work", jid: "shared@example" }, "synthetic-animation")
    })
    var animation = findChild(viewer, "viewerAnimatedMediaSurface")
    verify(animation !== null)
    tryCompare(animation, "status", Image.Ready, 5000)
    compare(animation.playing, true)

    verify(coordinator.acquire("dropdown",
      { account: "home", jid: "shared@example" }, "another-animation"))
    tryCompare(animation, "playing", false)
  }

  function test_real_synthetic_video_gif_and_webp_decode_offscreen() {
    var videoBubble = createTemporaryObject(genericMediaBubbleComponent, testCase,
      { message: video(fixturePath("synthetic.mp4")),
        activePlaybackId: "synthetic-video" })
    verify(videoBubble !== null)
    var videoSurface = findChild(videoBubble, "videoMediaSurface")
    var player = findChild(videoBubble, "videoMediaPlayer")
    verify(videoSurface !== null)
    verify(player !== null)
    tryVerify(function() {
      return videoSurface.duration > 0 && !videoSurface.failed
    }, 5000)
    videoSurface.togglePlayback()
    tryCompare(videoSurface, "playing", true, 5000)
    videoBubble.surfaceActive = false
    tryCompare(videoSurface, "playing", false, 1000)

    var gifBubble = createTemporaryObject(genericMediaBubbleComponent, testCase,
      { message: {
          id: "real-gif", media_type: "gif", mime_type: "image/gif",
          local_path: fixturePath("synthetic.gif")
        } })
    verify(gifBubble !== null)
    var animation = findChild(gifBubble, "animatedMediaSurface")
    verify(animation !== null)
    tryCompare(animation, "status", Image.Ready, 5000)

    var webpBubble = createTemporaryObject(genericMediaBubbleComponent, testCase,
      { message: stillImage(fixturePath("synthetic.webp"), "image/webp") })
    verify(webpBubble !== null)
    var image = findChild(webpBubble, "animatedMediaSurface")
    verify(image !== null)
    tryCompare(image, "status", Image.Ready, 5000)
  }

  function test_real_portrait_video_drives_preview_size_from_decoded_metadata() {
    var portraitBubble = createTemporaryObject(genericMediaBubbleComponent, testCase,
      { message: video(fixturePath("portrait.mp4")) })
    verify(portraitBubble !== null)
    var videoSurface = findChild(portraitBubble, "videoMediaSurface")
    verify(videoSurface !== null)
    tryVerify(function() {
      return videoSurface.intrinsicWidth > 0 && videoSurface.intrinsicHeight > 0
    }, 5000)
    compare(videoSurface.intrinsicWidth, 24)
    compare(videoSurface.intrinsicHeight, 40)
    tryCompare(portraitBubble, "previewHeight", 315, 5000)
    tryCompare(portraitBubble, "implicitHeight", 315, 5000)
  }

  function test_surface_coordinator_allows_only_one_timeline_player() {
    coordinatedPlaybackId = ""
    var first = createTemporaryObject(genericMediaBubbleComponent, testCase,
      { message: video(fixturePath("synthetic.mp4")) })
    var secondMessage = video(fixturePath("portrait.mp4"))
    secondMessage.id = "second-video"
    var second = createTemporaryObject(genericMediaBubbleComponent, testCase,
      { message: secondMessage })
    verify(first !== null)
    verify(second !== null)
    first.playbackRequested.connect(function(messageId) {
      coordinatedPlaybackId = messageId
      first.activePlaybackId = messageId
      second.activePlaybackId = messageId
    })
    second.playbackRequested.connect(function(messageId) {
      coordinatedPlaybackId = messageId
      first.activePlaybackId = messageId
      second.activePlaybackId = messageId
    })

    var firstPlayer = findChild(first, "videoMediaSurface")
    var secondPlayer = findChild(second, "videoMediaSurface")
    verify(firstPlayer !== null)
    verify(secondPlayer !== null)
    tryVerify(function() {
      return firstPlayer.duration > 0 && secondPlayer.duration > 0
    }, 5000)

    firstPlayer.togglePlayback()
    tryCompare(firstPlayer, "playing", true, 5000)
    compare(coordinatedPlaybackId, "synthetic-video")
    compare(secondPlayer.playing, false)

    secondPlayer.togglePlayback()
    tryCompare(secondPlayer, "playing", true, 5000)
    tryCompare(firstPlayer, "playing", false, 1000)
    compare(coordinatedPlaybackId, "second-video")
  }

  function test_paused_video_keeps_its_decoded_frame_visible() {
    var bubble = createTemporaryObject(genericMediaBubbleComponent, testCase,
      { message: video(fixturePath("synthetic.mp4")),
        activePlaybackId: "synthetic-video" })
    verify(bubble !== null)
    var videoSurface = findChild(bubble, "videoMediaSurface")
    var poster = findChild(bubble, "videoPosterOverlay")
    verify(videoSurface !== null)
    verify(poster !== null)
    tryVerify(function() { return videoSurface.duration > 0 }, 5000)
    compare(videoSurface.hasStartedPlayback, false)
    compare(videoSurface.posterShown, true)
    videoSurface.togglePlayback()
    tryCompare(videoSurface, "playing", true, 5000)
    tryVerify(function() { return videoSurface.hasDecodedFrame }, 5000)
    compare(videoSurface.hasStartedPlayback, true)
    compare(videoSurface.posterShown, false)
    videoSurface.togglePlayback()
    tryCompare(videoSurface, "playing", false, 1000)
    compare(videoSurface.posterShown, false)
  }

  function test_suspended_timed_media_keeps_its_decoded_preview_data() {
    return [
      { tag: "video", mediaType: "video" },
      { tag: "gif-video", mediaType: "gif" }
    ]
  }

  function test_suspended_timed_media_keeps_its_decoded_preview(data) {
    var message = video(fixturePath("synthetic.mp4"))
    message.media_type = data.mediaType
    var bubble = createTemporaryObject(genericMediaBubbleComponent, testCase,
      { message: message, activePlaybackId: "synthetic-video" })
    verify(bubble !== null)
    var videoSurface = findChild(bubble, "videoMediaSurface")
    verify(videoSurface !== null)
    tryVerify(function() { return videoSurface.duration > 0 }, 5000)
    videoSurface.togglePlayback()
    tryCompare(videoSurface, "playing", true, 5000)
    tryVerify(function() {
      return videoSurface.hasDecodedFrame && videoSurface.position > 0
    }, 5000)

    bubble.activePlaybackId = ""
    tryCompare(videoSurface, "playing", false, 1000)
    compare(videoSurface.hasStartedPlayback, true)
    compare(videoSurface.posterShown, false)
    verify(videoSurface.hasDecodedFrame)
    verify(videoSurface.position > 0)
  }

  function test_inactive_timed_media_releases_its_preview() {
    var bubble = createTemporaryObject(genericMediaBubbleComponent, testCase,
      { message: video(fixturePath("synthetic.mp4")),
        activePlaybackId: "synthetic-video" })
    verify(bubble !== null)
    var videoSurface = findChild(bubble, "videoMediaSurface")
    verify(videoSurface !== null)
    tryVerify(function() { return videoSurface.duration > 0 }, 5000)
    videoSurface.togglePlayback()
    tryCompare(videoSurface, "playing", true, 5000)

    bubble.surfaceActive = false
    tryCompare(videoSurface, "playing", false, 1000)
    compare(videoSurface.hasStartedPlayback, false)
    compare(videoSurface.posterShown, true)
    compare(videoSurface.position, 0)
  }

  function test_local_media_urls_encode_reserved_filename_characters() {
    var bubble = createTemporaryObject(genericMediaBubbleComponent, testCase,
      { message: video("__demo_video__") })
    verify(bubble !== null)
    compare(String(bubble.localUrlFor({ local_path: "/tmp/Synthetic #1?.mp4" })),
      "file:///tmp/Synthetic%20%231%3F.mp4")
    compare(MediaModel.encodedFileUrl("/tmp/Synthetic #1?.mp4"),
      "file:///tmp/Synthetic%20%231%3F.mp4")
  }

  function test_media_model_bounds_invalid_dimensions_and_formats_time() {
    compare(MediaModel.previewHeight(400,
      { media_width: 1, media_height: 10000 }, 140, 315), 225)
    compare(MediaModel.formatDuration(65000), "1:05")
    compare(MediaModel.formatDuration(3661000), "1:01:01")
  }
}
