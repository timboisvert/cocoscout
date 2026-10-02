// TicketPricing's math in the browser (app/services/ticket_pricing.rb), so a
// total shown before checkout is the total checkout charges: our fee per paid
// ticket, and card processing grossed up once per order when buyers pay the
// fees. `base` is the tickets after discounts plus any tax added on top;
// `paid` is how many of them cost something.
export function orderTotalCents({ base, paid, feeMode, platformFee, perMille, fixed }) {
    if (base === 0) return 0
    if (feeMode !== "buyer") return base
    return grossUp(base + platformFee * paid, perMille, fixed)
}

export function processingCents(total, perMille, fixed) {
    return Math.floor((total * perMille + 500) / 1000) + fixed
}

// The smallest charge that leaves exactly `needed` after processing.
export function grossUp(needed, perMille, fixed) {
    let total = Math.floor(((needed + fixed) * 1000) / (1000 - perMille)) - 2
    while (total - processingCents(total, perMille, fixed) < needed) total += 1
    return total
}

export function money(cents) {
    return "$" + (cents / 100).toFixed(2)
}
