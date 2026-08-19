// Work time regions ("day parts") an organization staffs by — the JS twin of
// Organization#staffing_day_part_for / StaffUnavailability#covers_time?.
// `parts` is the org's declared list: [{ key, name, starts: "HH:MM", ends: "HH:MM" }, …].

const DEFAULT_DAY_PARTS = [
    { key: "afternoon", name: "Afternoon", starts: "00:00", ends: "17:00" },
    { key: "evening", name: "Evening", starts: "17:00", ends: "24:00" }
]

// "17:30" → 1050; "24:00" → 1440; anything malformed → null.
function minuteOfDay(value) {
    const match = /^(\d{1,2}):(\d{2})$/.exec(String(value || "").trim())
    if (!match) return null
    const hour = parseInt(match[1], 10)
    const min = parseInt(match[2], 10)
    if (hour === 24 && min === 0) return 1440
    if (hour > 23 || min > 59) return null
    return hour * 60 + min
}

// The key of the region a "HH:MM" start time falls in, or null in a gap.
// A region whose end is at or before its start wraps past midnight.
export function dayPartFor(hhmm, parts) {
    const minute = minuteOfDay(hhmm)
    if (minute === null) return null
    const list = Array.isArray(parts) && parts.length ? parts : DEFAULT_DAY_PARTS
    const found = list.find(part => {
        const starts = minuteOfDay(part.starts)
        const ends = minuteOfDay(part.ends)
        if (starts === null || ends === null) return false
        return ends > starts ? (minute >= starts && minute < ends) : (minute >= starts || minute < ends)
    })
    return found ? found.key : null
}

// Does an unavailability entry ({ date, scope }) cover a shift on `dateIso`
// starting in region `dayPart`? "all_day" covers everything on the date.
export function entryCovers(entry, dateIso, dayPart) {
    if (entry.date !== dateIso) return false
    return entry.scope === "all_day" || (dayPart !== null && entry.scope === dayPart)
}
