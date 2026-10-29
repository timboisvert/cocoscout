# frozen_string_literal: true

require "csv"

# Giving tickets away: a manager names the people (or pastes a guest list),
# picks a ticket type, and each person gets a real order — free, no card, no
# fees — with the normal email and QR codes. Comps take seats like any other
# ticket, so a full show says so. All of them are given, or none.
class TicketComps
  class Error < StandardError; end

  Guest = Data.define(:name, :email, :tier, :quantity)
  # A pasted line that can't be given as it is, or a repeat left out.
  Problem = Data.define(:line, :text, :reason)
  Paste = Data.define(:guests, :problems, :repeats)

  # What a pasted list would give, said before anything's given: who gets
  # what, the total against the date's comps, the seats and the giver's
  # allowance left, and whatever stops it. ready? when it can all be given.
  Preview = Data.define(:paste, :total, :comps_left, :allowance_left, :seats, :email_them, :blockers) do
    def guests = paste.guests
    def ready? = guests.any? && paste.problems.empty? && blockers.empty?

    # The one thing to fix, for the alert when it isn't ready.
    def stopper
      blockers.first || paste.problems.first&.then { |p| "Line #{p.line}: #{p.reason}" } || "Paste at least one person, one per line."
    end
  end

  # A pasted guest list, one person per line: "Name, email", "Name <email>",
  # columns copied from a spreadsheet (tabs) or a CSV, or just an email (who
  # then goes on the guest list by it), with an optional count ("Name,
  # email, 2") and a ticket type's name to override the one picked. A first
  # line of column names (no email, no count, a "Name" or "Email") is
  # skipped. A repeated email is left out and said so; a line it can't read
  # is kept as a problem, never dropped. email_them: every line needs an email.
  def self.parse(text, listing:, default_tier:, email_them: false)
    tiers = listing.ticket_tiers.active.reject(&:bundle?)
    guests = []
    problems = []
    repeats = []
    seen = {}
    text.to_s.lines.each.with_index(1) do |raw, number|
      line = raw.strip
      next if line.empty?

      parts = split_columns(line)
      next if parts.empty? # a spreadsheet's empty row: ",,,"
      next if guests.empty? && problems.empty? && repeats.empty? && header?(parts)

      problem = ->(reason) { problems << Problem.new(line: number, text: line.first(120), reason: reason) }
      emails = parts.flat_map { |p| p.scan(FollowerIntake::EMAIL) }
      next problem.call("More than one email on this line.") if emails.size > 1
      if (bad = parts.find { |p| p.include?("@") && !p.match?(FollowerIntake::EMAIL) })
        next problem.call("#{bad} isn't an email address.")
      end

      email = emails.first&.downcase
      at = email ? parts.index { |p| p.match?(FollowerIntake::EMAIL) } : parts.size
      count = tier = nil
      before = []
      after = []
      parts.each_with_index do |part, i|
        if i == at
          # "Rosa Delgado <rosa@example.com>": the name shares the column.
          rest = part.sub(/<?#{Regexp.escape(part[FollowerIntake::EMAIL])}>?/, "").delete('"<>').squish
          before << rest if rest.present?
        elsif count.nil? && part.match?(/\A\d+\z/)
          count = part.to_i
        elsif tier.nil? && (match = tiers.find { |t| part.casecmp?(t.name) })
          tier = match
        else
          (i < at ? before : after) << part.delete('"').squish
        end
      end
      # Spreadsheet columns "First, Last, Email": the name is what comes before
      # the email ("email, Name" has it after; other columns after it are ignored).
      name = (before.presence || after).join(" ").squish.presence || email

      if name.nil?
        problem.call("No name or email on this line.")
      elsif count && !count.between?(1, 99)
        problem.call("#{count} isn't a number of tickets to give.")
      elsif email_them && email.nil?
        problem.call("No email to send #{name} their tickets.")
      elsif email && seen[email]
        repeats << Problem.new(line: number, text: line.first(120), reason: "Same email as line #{seen[email]}, so left out.")
      else
        seen[email] = number if email
        guests << Guest.new(name: name.first(120), email: email, tier: tier || default_tier, quantity: count || 1)
      end
    end
    Paste.new(guests: guests, problems: problems, repeats: repeats)
  end

  # A line's columns: tabs from a spreadsheet, else commas or semicolons, with
  # a CSV's quotes ("Delgado, Rosa",rosa@example.com) honored.
  def self.split_columns(line)
    sep = [ "\t", ",", ";" ].find { |s| line.include?(s) }
    columns = if sep.nil? then [ line ]
    else
      begin
        CSV.parse_line(line, col_sep: sep).to_a
      rescue CSV::MalformedCSVError
        line.split(sep)
      end
    end
    columns.map { |c| c.to_s.strip }.reject(&:empty?)
  end

  # A CSV's header row: no email, no count, and a column called Name or Email.
  def self.header?(parts)
    parts.none? { |p| p.include?("@") || p.match?(/\A\d+\z/) } && parts.any? { |p| p.match?(/\b(?:name|e-?mail)\b/i) }
  end

  # A pasted list checked before it's given (Preview). tier: the one picked
  # for the batch; allowance_left: the most this giver may give (nil, no limit).
  def self.preview(listing, text, tier:, email_them:, allowance_left: nil)
    paste = parse(text, listing: listing, default_tier: tier, email_them: email_them)
    guests = paste.guests.select(&:tier)
    total = paste.guests.sum(&:quantity)
    inventory = Ticketing::Inventory.new(listing)
    requests = TicketCheckout.seat_requests(guests.group_by(&:tier).transform_values { |gs| gs.sum(&:quantity) })
    seats = requests.map { |t, asked| { tier: t, asked: asked, left: inventory.remaining(tier: t) } }
    comps_left = listing.comps_left

    blockers = []
    blockers << "Pick a ticket type." if guests.size < paste.guests.size
    blockers << "This show was canceled." if listing.status == "canceled" || listing.show.canceled
    blockers << "Comps are off for this show." unless listing.effective_comps_enabled
    if comps_left && total > comps_left
      blockers << "This date has #{comps_left.zero? ? 'no' : comps_left} #{'comp'.pluralize(comps_left)} left to give, and this list is #{total}."
    end
    if allowance_left && total > allowance_left
      blockers << "You can give #{allowance_left.zero? ? 'no' : allowance_left} more #{'comp'.pluralize(allowance_left)} for this date, and this list is #{total}."
    end
    short = seats.select { |s| s[:left] && s[:asked] > s[:left] }
    short.each { |s| blockers << "#{s[:tier].name} has #{s[:left]} #{'seat'.pluralize(s[:left])} left, and this list needs #{s[:asked]}." }
    if short.empty? && (overall = inventory.remaining) && (needed = requests.values.sum) > overall
      blockers << "The show has #{overall} #{'seat'.pluralize(overall)} left, and this list needs #{needed}."
    end

    Preview.new(paste: paste, total: total, comps_left: comps_left, allowance_left: allowance_left, seats: seats,
                email_them: email_them, blockers: blockers)
  end

  def self.give!(listing, guests, by:, note: nil, email_them: true)
    raise Error, "Add at least one person." if guests.empty?
    raise Error, "This show was canceled." if listing.status == "canceled" || listing.show.canceled
    # The comp rules (CompRules): off, nobody gives any; a date with a limit
    # gives no more than it has left, whoever is giving.
    raise Error, "Comps are off for this show." unless listing.effective_comps_enabled
    if (left = listing.comps_left) && left < guests.sum { |g| g.quantity.to_i }
      raise Error, left.zero? ? "This date has no comps left to give." : "This date has #{left} #{'comp'.pluralize(left)} left to give."
    end

    bad = guests.find { |g| g.name.blank? || g.quantity.to_i < 1 || g.tier.nil? || (g.email.present? && !g.email.match?(URI::MailTo::EMAIL_REGEXP)) }
    raise Error, "Check #{bad.name.presence || 'each row'}: every person needs a name, a ticket type and a count, and a valid email if there is one." if bad

    requests = TicketCheckout.seat_requests(guests.group_by(&:tier).transform_values { |gs| gs.sum(&:quantity) })
    orders = []
    Ticketing::Inventory.reserve!(listing, requests) do
      guests.each do |guest|
        order = TicketOrder.create!(organization: listing.organization, ticket_listing: listing, status: "paid", paid_at: Time.current,
                                    channel: "comp", money_path: "none", fee_mode: listing.effective_fee_mode,
                                    buyer_name: guest.name.squish, buyer_email: guest.email.presence,
                                    issued_by: by, note: note.to_s.squish.presence)
        # A 4-pack given is four tickets, one per person.
        guest.quantity.times do
          guest.tier.seat_prices.each do |cents|
            order.tickets.create!(ticket_tier: guest.tier.base_tier, bundle_tier: (guest.tier if guest.tier.bundle?), ticket_listing: listing,
                                  status: "valid", price_cents: cents, discount_cents: cents)
          end
        end
        TicketCheckout.price!(order)
        orders << order
      end
    end

    orders.each { |order| TicketOrderConfirmationJob.perform_later(order.id) if email_them && order.buyer_email.present? }
    TicketingAfterSaleJob.perform_later(orders.last.id, together: orders.map(&:id))
    orders
  rescue Ticketing::Inventory::SoldOut
    raise Error, sold_out_message(listing, requests)
  end

  # Which type ran short, and where its seats went: "Front Row VIP has no
  # seats left: 3 sold here, 9 on Ticket Tailor."
  def self.sold_out_message(listing, requests)
    inventory = Ticketing::Inventory.new(listing)
    tier, = (requests || {}).find { |t, seats| (left = inventory.remaining(tier: t)) && left < seats }
    return "That's more than the seats left. Raise the seats on the show if the room has space." unless tier

    left = inventory.remaining(tier: tier)
    return "#{tier.name} has only #{left} #{left == 1 ? 'seat' : 'seats'} left." if left.positive?

    where = [ ("#{inventory.sold(tier: tier)} sold here" if inventory.sold(tier: tier).positive?), inventory.outside_words(tier: tier).presence ].compact
    "#{tier.name} has no seats left#{": #{where.to_sentence}" if where.any?}. Raise its seats if the room has space."
  end
end
