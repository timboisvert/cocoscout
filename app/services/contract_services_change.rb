# frozen_string_literal: true

# Change services and prices (2026-10-16): the small amend job for which
# services each date gets and what they cost, on any date that isn't settled
# yet. The deal is left alone; pending payments are re-billed to match and
# anything paid stays as it is. Settled dates keep exactly what they had,
# whatever the form posts, so a paid night can't be re-priced after the fact.
class ContractServicesChange
  Change = Struct.new(:words, :delta, :direction, keyword_init: true)

  attr_reader :contract

  def initialize(contract)
    @contract = contract
  end

  def rentals
    @rentals ||= contract.space_rentals.includes(:shows).order(:starts_at).to_a
  end

  # Each date as the services form reads it.
  def bookings
    rentals.map do |r|
      { "starts_at" => r.starts_at.iso8601, "duration" => ((r.ends_at - r.starts_at) / 1.hour).round(1),
        "event_type" => r.shows.first&.event_type || "show" }
    end
  end

  # The settled dates' start times: paid, in a payout run, or with the night's
  # numbers confirmed.
  def settled_times
    @settled_times ||= rentals.select { |r| ContractDateChanges.settled_for?(contract: contract, rental: r, shows: r.shows.to_a) }
                              .map(&:starts_at)
  end

  # The posted (or staged) lines, with every settled date put back the way the
  # contract has it now.
  def merge(lines)
    settled = settled_times.map(&:to_i).to_set
    current = contract.draft_services
    locked = ->(event) { settled.include?(self.class.time_key(event["starts_at"])) }

    merged = Array(lines).map do |line|
      next line unless line["per_event"]

      old = find_line(current, line)
      kept = Array(old&.dig("events")).select(&locked).map { |event| priced_as_billed(event, old, line) }
      with_events(line, Array(line["events"]).reject(&locked) + kept)
    end

    # A service taken off every open date still has the settled ones it had.
    current.each do |old|
      next unless old["per_event"] && find_line(merged, old).nil?

      kept = Array(old["events"]).select(&locked)
      merged << with_events(old, kept) if kept.any?
    end
    merged
  end

  # What's different, date by date, grouped where several dates change the
  # same way: "Tue, Oct 27: Booth Tech $50.00 to $0.00".
  def changes(new_lines)
    old_lines = contract.draft_services
    rows = []
    (old_lines + new_lines).uniq { |l| line_key(l) }.each do |sample|
      old = find_line(old_lines, sample)
      new = find_line(new_lines, sample)
      name = sample["name"]
      direction = (new || old)["direction"].presence || "incoming"

      if (old.nil? || !old["per_event"]) && (new.nil? || !new["per_event"])
        before = old ? Contract.service_line_total(old) : nil
        after = new ? Contract.service_line_total(new) : nil
        next if before == after

        words = if before.nil? then "#{name} added"
        elsif after.nil? then "#{name} removed"
        else "#{name} #{money(before)} to #{money(after)}"
        end
        rows << [ nil, words, (after || 0) - (before || 0), direction ]
        next
      end

      old_events = per_date(old)
      new_events = per_date(new)
      (old_events.keys | new_events.keys).each do |key|
        was = old_events[key]
        now = new_events[key]
        next if was == now

        words = if was.nil? then "#{name} added"
        elsif now.nil? then "#{name} removed"
        elsif was[:amount] != now[:amount] then "#{name} #{money(was[:amount])} to #{money(now[:amount])}"
        else "#{name} #{hours(was[:hours])} to #{hours(now[:hours])}"
        end
        rows << [ key, words, (now&.dig(:amount) || 0) - (was&.dig(:amount) || 0), direction ]
      end
    end

    rows.group_by { |_, words, _, direction| [ words, direction ] }.map do |(words, direction), group|
      times = group.map(&:first).compact.sort.map { |t| Time.zone.at(t) }
      label = case times.size
      when 0 then nil
      when 1 then times.first.strftime("%a, %b %-d")
      else times.map { |t| t.strftime("%b %-d") }.to_sentence
      end
      # "Mar 5 and Mar 6: Booth Tech $50.00 to $120.00 each"
      words = "#{words} each" if times.size > 1 && words.include?(" to ")
      Change.new(words: [ label, words ].compact.join(": "), delta: group.sum { |row| row[2] }.round(2), direction: direction)
    end.sort_by { |c| c.words }
  end

  # Re-bill the pending payments to the new lines and record the change, with
  # the reason, in the contract's history. Returns the new version.
  def apply!(lines, reason:, user:)
    merged = merge(lines)
    contract.ensure_baseline_version!(created_by: user)
    contract.transaction do
      contract.reconcile_service_payments!(merged)
      contract.update!(draft_data: contract.draft_data.except("services_change"))
    end
    summary = [ "Changed services and prices", reason.to_s.strip.presence ].compact.join(": ")
    contract.cut_version!(requires_signature: false, created_by: user, change_summary: summary)
  end

  def self.time_key(value)
    (value.is_a?(String) ? Time.zone.parse(value) : value)&.to_i
  rescue ArgumentError
    nil
  end

  private

  # A settled date keeps the price it was billed at, even when the line's
  # usual price changes for the open dates.
  def priced_as_billed(event, old_line, new_line)
    return event if event.key?("unit_price")

    was = old_line["unit_price"].to_f.round(2)
    was == new_line["unit_price"].to_f.round(2) ? event : event.merge("unit_price" => was)
  end

  def find_line(lines, sample)
    lines.find { |l| line_key(l) == line_key(sample) }
  end

  def line_key(line)
    line["service_id"].present? ? "id:#{line['service_id']}" : "name:#{line['name'].to_s.downcase}"
  end

  def with_events(line, events)
    events = events.sort_by { |e| self.class.time_key(e["starts_at"]).to_i }
    line.merge("per_event" => true, "events" => events, "quantity" => events.sum { |e| e["hours"].to_f }.round(2))
  end

  # { epoch => { hours:, amount: } } for one per-event line.
  def per_date(line)
    return {} unless line && line["per_event"]

    hourly = line["unit"] == "hourly"
    Array(line["events"]).each_with_object({}) do |e, out|
      key = self.class.time_key(e["starts_at"])
      next unless key

      price = (e["unit_price"] || line["unit_price"]).to_f
      out[key] = { hours: e["hours"].to_f, amount: (price * (hourly ? e["hours"].to_f : 1)).round(2) }
    end
  end

  def money(amount)
    ActionController::Base.helpers.number_to_currency(amount)
  end

  def hours(n)
    n = n.to_f
    "#{n % 1 == 0 ? n.to_i : n} #{n == 1 ? 'hr' : 'hrs'}"
  end
end
