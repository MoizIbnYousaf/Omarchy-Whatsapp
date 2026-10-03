.pragma library

// Emoji data comes from Omarchy's own picker (shell/plugins/emojis/emojis.json,
// entries of { e: emoji, k: keywords }). A short list keeps the picker useful
// if that file is missing.
var FALLBACK = [
  { e: "\ud83d\ude00", k: "grinning face smile happy" },
  { e: "\ud83d\ude02", k: "face with tears of joy laugh" },
  { e: "\ud83d\ude0a", k: "smiling face blush happy" },
  { e: "\ud83d\ude0d", k: "heart eyes love" },
  { e: "\ud83d\ude09", k: "wink" },
  { e: "\ud83d\ude0e", k: "cool sunglasses" },
  { e: "\ud83e\udd14", k: "thinking" },
  { e: "\ud83d\ude22", k: "crying sad" },
  { e: "\ud83d\ude2e", k: "surprised open mouth wow" },
  { e: "\ud83d\ude4f", k: "folded hands please thanks pray" },
  { e: "\ud83d\udc4d", k: "thumbs up like yes" },
  { e: "\ud83d\udc4e", k: "thumbs down no" },
  { e: "\ud83d\udc4f", k: "clapping hands applause" },
  { e: "\ud83d\udcaa", k: "flexed biceps strong" },
  { e: "\u2764\ufe0f", k: "red heart love" },
  { e: "\ud83d\udd25", k: "fire hot lit" },
  { e: "\ud83c\udf89", k: "party popper celebrate" },
  { e: "\u2705", k: "check mark done yes" },
  { e: "\ud83d\ude4c", k: "raising hands hooray" },
  { e: "\ud83d\udc40", k: "eyes look" }
]

function parse(raw) {
  try {
    var data = JSON.parse(String(raw || ""))
    var values = Array.isArray(data) ? data.filter(function(item) {
      return item && typeof item.e === "string" && item.e !== ""
    }) : []
    return values.length > 0 ? values : FALLBACK
  } catch (error) {
    return FALLBACK
  }
}

function filter(emojis, query, limit) {
  var values = Array.isArray(emojis) && emojis.length > 0 ? emojis : FALLBACK
  var needle = String(query || "").trim().toLowerCase()
  var max = Math.max(0, Number(limit === undefined ? 400 : limit))
  var out = []
  for (var i = 0; i < values.length && out.length < max; i++) {
    var item = values[i]
    if (!needle || String(item.k || "").toLowerCase().indexOf(needle) >= 0) out.push(item)
  }
  return out
}

// Most recent first, without duplicates, bounded.
function remember(recent, emoji, limit) {
  var next = [emoji]
  var values = Array.isArray(recent) ? recent : []
  for (var i = 0; i < values.length && next.length < (limit || 16); i++)
    if (values[i] !== emoji) next.push(values[i])
  return next
}

// Themes as on the phone. Omarchy's list follows Unicode's order, so each
// theme starts at its first emoji; a list in any other order stays one group.
var GROUPS = [
  { id: "smileys", label: "Smileys & emotion", icon: "\ud83d\ude00", first: "\ud83d\ude00" },
  { id: "people", label: "People & body", icon: "\ud83d\udc4b", first: "\ud83d\udc4b" },
  { id: "animals", label: "Animals & nature", icon: "\ud83d\udc3b", first: "\ud83d\udc35" },
  { id: "food", label: "Food & drink", icon: "\ud83c\udf54", first: "\ud83c\udf47" },
  { id: "travel", label: "Travel & places", icon: "\ud83d\ude97", first: "\ud83c\udf0d" },
  { id: "activities", label: "Activities", icon: "\u26bd", first: "\ud83c\udf83" },
  { id: "objects", label: "Objects", icon: "\ud83d\udca1", first: "\ud83d\udc53" },
  { id: "symbols", label: "Symbols", icon: "\ud83d\udd23", first: "\ud83c\udfe7" },
  { id: "flags", label: "Flags", icon: "\ud83c\udff3\ufe0f", first: "\ud83c\udfc1" }
]

function groups(emojis) {
  var values = Array.isArray(emojis) && emojis.length > 0 ? emojis : FALLBACK
  var starts = []
  var previous = -1
  for (var g = 0; g < GROUPS.length; g++) {
    var at = -1
    for (var i = previous + 1; i < values.length; i++) {
      if (values[i].e === GROUPS[g].first) { at = i; break }
    }
    if (at < 0) return [{ id: "all", label: "Emoji", icon: "\ud83d\ude00", items: values.slice() }]
    starts.push(at)
    previous = at
  }
  var out = []
  for (var k = 0; k < GROUPS.length; k++) {
    var end = k + 1 < GROUPS.length ? starts[k + 1] : values.length
    var from = k === 0 ? 0 : starts[k]
    out.push({ id: GROUPS[k].id, label: GROUPS[k].label, icon: GROUPS[k].icon,
               items: values.slice(from, end) })
  }
  return out
}

// One grid with a full-width header row before each theme: a header fills
// the first cell of a row and blank cells complete it and the theme's last
// row, so every theme starts on a row of its own. `sections` gives where.
function layout(emojis, recent, columns) {
  var width = Math.max(1, Number(columns || 8))
  var parts = groups(emojis)
  var mine = Array.isArray(recent) ? recent : []
  if (mine.length > 0) parts.unshift({ id: "recent", label: "Recent", icon: "\ud83d\udd58",
    items: mine.map(function(emoji) { return { e: emoji, k: "recent" } }) })
  var items = []
  var sections = []
  function pad() { while (items.length % width !== 0) items.push({ kind: "blank" }) }
  for (var p = 0; p < parts.length; p++) {
    pad()
    sections.push({ id: parts[p].id, label: parts[p].label, icon: parts[p].icon, index: items.length })
    items.push({ kind: "header", label: parts[p].label })
    pad()
    for (var j = 0; j < parts[p].items.length; j++)
      items.push({ kind: "emoji", e: parts[p].items[j].e, k: parts[p].items[j].k })
  }
  pad()
  return { items: items, sections: sections }
}

// The theme a grid index belongs to.
function sectionAt(sections, index) {
  var found = sections.length > 0 ? sections[0].id : ""
  for (var i = 0; i < sections.length; i++)
    if (sections[i].index <= index) found = sections[i].id
  return found
}
