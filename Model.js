.pragma library

function emptyStatus() {
  return {
    ok: false,
    timezone: "",
    latitude: 0,
    longitude: 0,
    locationSource: "",
    sunrise: "",
    sunset: "",
    estimated: false,
    running: false,
    paused: false,
    generated: false,
    scheduledTemperature: null,
    scheduledSince: "",
    nextTemperature: null,
    nextAt: "",
    actualTemperature: null,
    dayTemp: null,
    eveningTemp: 0,
    nightTemp: 0,
    steps: []
  }
}

function parseStatus(raw) {
  try {
    var data = JSON.parse(String(raw || "").trim())
    if (!data || typeof data !== "object") return emptyStatus()
    var s = emptyStatus()
    s.ok = true
    s.timezone = String(data.timezone || "")
    s.latitude = Number(data.latitude) || 0
    s.longitude = Number(data.longitude) || 0
    s.locationSource = String(data.location_source || "")
    s.sunrise = String(data.sunrise || "")
    s.sunset = String(data.sunset || "")
    s.estimated = data.estimated === true
    s.running = data.running === true
    s.paused = data.paused === true
    s.generated = data.generated === true
    s.scheduledTemperature = normaliseTemp(data.scheduled_temperature)
    s.scheduledSince = String(data.scheduled_since || "")
    s.nextTemperature = normaliseTemp(data.next_temperature)
    s.nextAt = String(data.next_at || "")
    s.actualTemperature = normaliseTemp(data.actual_temperature)
    s.dayTemp = normaliseTemp(data.day_temp)
    s.eveningTemp = Number(data.evening_temp) || 0
    s.nightTemp = Number(data.night_temp) || 0
    return s
  } catch (e) {
    return emptyStatus()
  }
}

// null is meaningful: it is the untinted day profile, not a missing value.
function normaliseTemp(value) {
  return (value === null || value === undefined) ? null : Number(value)
}

function parseSteps(raw) {
  var out = []
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (!line || line.charAt(0) === "#") continue
    // "Fri 17:30   5000K"  or  "Sat 06:13   day"
    var parts = line.split(/\s+/)
    if (parts.length < 3) continue
    var value = parts[2]
    out.push({
      day: parts[0],
      time: parts[1],
      temperature: value === "day" ? null : Number(value.replace("K", "")),
      label: value === "day" ? "off" : value
    })
  }
  return out
}

function tempLabel(temp) {
  return temp === null ? "off" : (String(temp) + "K")
}

// How far through the ramp a temperature sits, 0 at the evening end and 1 at
// the deepest point. Interpolated in mireds so it matches how the ladder was
// built, and so the colour swatch tracks what the eye actually sees.
function rampFraction(temp, eveningTemp, nightTemp) {
  if (temp === null || !eveningTemp || !nightTemp) return 0
  if (eveningTemp === nightTemp) return 1
  var m = 1e6 / temp
  var a = 1e6 / eveningTemp
  var b = 1e6 / nightTemp
  var f = (m - a) / (b - a)
  return Math.max(0, Math.min(1, f))
}

// A rough sRGB rendering of a black-body temperature, for the swatch only.
// Tanner Helland's approximation; close enough to read as "this is the tint".
function temperatureColor(kelvin) {
  if (kelvin === null) return Qt.rgba(1, 1, 1, 1)
  var t = Math.max(1000, Math.min(20000, kelvin)) / 100
  var r, g, b

  if (t <= 66) {
    r = 255
  } else {
    r = 329.698727446 * Math.pow(t - 60, -0.1332047592)
  }

  if (t <= 66) {
    g = 99.4708025861 * Math.log(t) - 161.1195681661
  } else {
    g = 288.1221695283 * Math.pow(t - 60, -0.0755148492)
  }

  if (t >= 66) {
    b = 255
  } else if (t <= 19) {
    b = 0
  } else {
    b = 138.5177312231 * Math.log(t - 10) - 305.0447927307
  }

  return Qt.rgba(clamp01(r / 255), clamp01(g / 255), clamp01(b / 255), 1)
}

function clamp01(v) {
  if (!isFinite(v)) return 0
  return Math.max(0, Math.min(1, v))
}

function locationLabel(status) {
  if (!status.ok) return ""
  var lat = status.latitude.toFixed(2)
  var lon = status.longitude.toFixed(2)
  return lat + ", " + lon
}

function summaryLine(status) {
  if (!status.ok) return "Sunset Night Light"
  if (status.paused) return "Night light paused"
  if (!status.running) return "hyprsunset is not running"
  var now = tempLabel(status.scheduledTemperature)
  if (status.nextAt) return now + " · " + tempLabel(status.nextTemperature) + " at " + status.nextAt
  return now
}

// Which stage of the evening the ramp is in. Callers map this to a glyph --
// the names stay here so the indicator mark and the panel cannot disagree
// about where the boundaries are, while the glyphs live in the QML.
function rampStage(tinted, fraction) {
  if (!tinted) return "day"
  if (fraction < 0.34) return "dusk"
  if (fraction < 0.75) return "night"
  return "deep"
}

function stageLabel(stage) {
  if (stage === "day") return "Night light off"
  if (stage === "dusk") return "Warming"
  if (stage === "night") return "Warm"
  return "Warmest"
}

function pluginDirFromUrl(url) {
  var u = String(url || "")
  if (u.indexOf("file://") === 0) u = u.slice(7)
  return u.replace(/\/$/, "")
}
