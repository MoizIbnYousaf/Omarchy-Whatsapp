.pragma library

function mediaType(item) {
  return String(item && item.media_type || "").toLowerCase()
}

function mimeType(item) {
  return String(item && item.mime_type || "").toLowerCase()
}

function isGifVideo(item) {
  var media = mediaType(item)
  var mime = mimeType(item)
  return media === "gif" && mime !== "image/gif" && mime !== "image/webp"
}

function isVideo(item) {
  return isGifVideo(item) || mediaType(item) === "video"
    || mimeType(item).indexOf("video/") === 0
}

function isAnimatedImage(item) {
  var media = mediaType(item)
  var mime = mimeType(item)
  return !isVideo(item) && (mime === "image/gif" || mime === "image/webp"
    || media === "sticker")
}

function isImage(item) {
  return !isAnimatedImage(item) && !isVideo(item)
    && (mediaType(item) === "image" || mimeType(item).indexOf("image/") === 0)
}

function isAudio(item) {
  return mediaType(item) === "audio" || mimeType(item).indexOf("audio/") === 0
}

function isVisual(item) {
  return mediaType(item) === "album" || isVideo(item)
    || isAnimatedImage(item) || isImage(item)
}

function kind(item) {
  var items = item && item.album_items
  if (mediaType(item) === "album" && items
      && typeof items.length === "number" && items.length > 1) return "album"
  if (mediaType(item) === "location") return "location"
  if (String(item && item.local_path || "") === "") return "missing"
  if (isGifVideo(item)) return "gif-video"
  if (isVideo(item)) return "video"
  if (isAnimatedImage(item)) return "animated-image"
  if (isImage(item)) return "image"
  if (isAudio(item)) return "audio"
  return "document"
}

function aspectRatio(item, decodedWidth, decodedHeight) {
  var width = Number(decodedWidth || 0)
  var height = Number(decodedHeight || 0)
  if (!(width > 0 && height > 0)) {
    width = Number(item && (item.media_width || item.video_width || item.width) || 0)
    height = Number(item && (item.media_height || item.video_height || item.height) || 0)
  }
  var ratio = width > 0 && height > 0 ? width / height : 16 / 9
  return isFinite(ratio) && ratio >= 0.25 && ratio <= 4 ? ratio : 16 / 9
}

function previewHeight(width, item, minimum, maximum, decodedWidth, decodedHeight) {
  var available = Math.max(0, Number(width || 0))
  var lower = Math.max(0, Number(minimum || 0))
  var upper = Math.max(lower, Number(maximum || lower))
  return Math.max(lower, Math.min(upper,
    available / aspectRatio(item, decodedWidth, decodedHeight)))
}

function encodedFileUrl(path) {
  var value = String(path || "")
  if (value === "") return ""
  return "file://" + value.split("/").map(function(segment) {
    return encodeURIComponent(segment)
  }).join("/")
}

function formatDuration(milliseconds) {
  var total = Math.max(0, Math.floor(Number(milliseconds || 0) / 1000))
  var seconds = String(total % 60).padStart(2, "0")
  var minutes = Math.floor(total / 60) % 60
  var hours = Math.floor(total / 3600)
  return hours > 0 ? hours + ":" + String(minutes).padStart(2, "0") + ":" + seconds
    : minutes + ":" + seconds
}
