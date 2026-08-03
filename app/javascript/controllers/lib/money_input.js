// Money-field input hygiene. People paste amounts with dollar signs ("$25"),
// commas ("1,200"), or stray spaces — parseFloat turns those into NaN and the
// UI reads $0.00 while the typed text sits there looking fine. Keep the fields
// digits-and-dot only and parse forgivingly everywhere money is read.

// Parse a money string to a number, ignoring $ , spaces and anything else.
export function parseMoney(value) {
    return parseFloat(String(value ?? "").replace(/[^0-9.]/g, "")) || 0
}

// Scrub an input's value in place (call from the field's input event so a
// paste of "$25" instantly becomes "25"). Returns the cleaned value.
export function sanitizeMoneyField(input) {
    if (!input || typeof input.value !== "string") return ""
    const clean = input.value.replace(/[^0-9.]/g, "")
    if (clean !== input.value) input.value = clean
    return clean
}
