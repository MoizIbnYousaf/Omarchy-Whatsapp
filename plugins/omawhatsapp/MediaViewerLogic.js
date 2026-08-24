.pragma library

function boundedIndex(items, index) {
  if (!Array.isArray(items) || items.length === 0) return -1
  return Math.max(0, Math.min(items.length - 1, Number(index || 0)))
}

function nextIndex(items, current, delta) {
  if (!Array.isArray(items) || items.length < 2) return Number(current || 0)
  return (Number(current || 0) + Number(delta || 0) + items.length) % items.length
}

function boundedZoom(value) {
  return Math.max(0.5, Math.min(4, Number(value || 1)))
}
