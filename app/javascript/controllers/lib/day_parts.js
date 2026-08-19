// Work time regions ("day parts") an organization staffs by — the JS twin of
// Organization#staffing_day_part_keys_for / StaffUnavailability#covers_time?.
// `parts` is the org's turned-on catalog entries: [{ key, name, starts: "HH:MM", ends: "HH:MM" }, …]
// (StaffingDayParts::STAFFING_DAY_PART_CATALOG); regions overlap on purpose.

const DEFAULT_DAY_PARTS = [
    { key: "morning", name: "Morning", starts: "06:00", ends: "12:00" },
    { key: "afternoon", name: "Afternoon", starts: "12:00", ends: "17:00" },
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

// The keys of every region a "HH:MM" start time falls in ([] in a gap).
// A region whose end is at or before its start wraps past midnight.
export function dayPartsFor(hhmm, parts) {
    const minute = minuteOfDay(hhmm)
    if (minute === null) return []
    const list = Array.isArray(parts) && parts.length ? parts : DEFAULT_DAY_PARTS
    return list.filter(part => {
        const starts = minuteOfDay(part.starts)
        const ends = minuteOfDay(part.ends)
        if (starts === null || ends === null) return false
        return ends > starts ? (minute >= starts && minute < ends) : (minute >= starts || minute < ends)
    }).map(part => part.key)
}

// Does an unavailability entry ({ date, scope }) cover a shift on `dateIso`
// starting in regions `dayParts`? "all_day" covers everything on the date.
export function entryCovers(entry, dateIso, dayParts) {
    if (entry.date !== dateIso) return false
    return entry.scope === "all_day" || (dayParts || []).includes(entry.scope)
}
