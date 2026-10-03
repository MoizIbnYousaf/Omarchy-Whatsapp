.pragma library

// One color per person or chat, derived from the theme's accent so it follows
// the theme: the same hue turned by one of eight steps, the same strength.
function personColor(key, accent) {
  var text = String(key || "")
  if (!accent) return "#888888"
  if (text === "") return accent
  var hash = 0
  for (var i = 0; i < text.length; i++) hash = (hash * 31 + text.charCodeAt(i)) >>> 0
  var base = accent.hslHue >= 0 ? accent.hslHue : 0.6
  var saturation = Math.max(0.45, accent.hslSaturation)
  var lightness = Math.min(0.78, Math.max(0.62, accent.hslLightness))
  return Qt.hsla((base + (hash % 8) / 8) % 1, saturation, lightness, 1)
}

// An unsent draft reads amber in any theme: a fixed warm hue at the accent's
// strength, apart from the accent that typing and unread use.
function draftColor(accent) {
  if (!accent) return "#e0af68"
  var saturation = Math.max(0.55, accent.hslSaturation)
  var lightness = Math.min(0.74, Math.max(0.6, accent.hslLightness))
  return Qt.hsla(0.11, saturation, lightness, 1)
}

// Each linked account keeps one color, in the order the accounts are listed:
// the first is the accent, the next ones sit apart from it on the wheel.
function accountColor(index, accent) {
  if (!accent) return "#888888"
  var position = Math.max(0, Number(index) || 0)
  if (position === 0) return accent
  var steps = [1 / 3, 2 / 3, 1 / 6, 1 / 2, 5 / 6]
  var base = accent.hslHue >= 0 ? accent.hslHue : 0.6
  var saturation = Math.max(0.45, accent.hslSaturation)
  var lightness = Math.min(0.74, Math.max(0.58, accent.hslLightness))
  return Qt.hsla((base + steps[(position - 1) % steps.length]) % 1, saturation, lightness, 1)
}
