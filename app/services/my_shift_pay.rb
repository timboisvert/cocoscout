# frozen_string_literal: true

# The Getting paid card on My Shifts (Tim, 2026-10-15, "direction A"): the
# next money coming to someone in big type, then each recent day they worked
# with where its pay stands, in their words: waiting for approval, approved,
# on its way, deposited. Pay we sent without the payout provider confirming
# the deposit reads "sent", never "paid" (PayoutBatchItem#deposit_stage).
#
# A day's pay is its hours at the role's rate plus the card tips the payout
# run put on that date (the tips worksheet), so the days add up to what was
# deposited (Tim, 2026-10-15). Cash tips were in hand, never paid by us.
# Bonuses and reimbursements aren't for a day; My Payments lists them.
class MyShiftPay
  # stage: :waiting, :approved, :on_its_way, :deposited, :sent, :paid_directly
  # on: the date that goes with the stage (goes out, expected, deposited, sent)
  # cents: hours plus tips_cents
  Day = Data.define(:date, :hours, :cents, :tips_cents, :stage, :on)

  # stage: :on_its_way, :approved, :waiting or :caught_up (the last payment,
  # deposited or sent: settled_as). on: expected / goes-out / deposited date.
  Hero = Data.define(:stage, :cents, :on, :org, :sent_on, :hours, :settled_as)

  DAYS = 6
  RECENT = 90.days

  def initialize(people_ids, today: Date.current)
    @people_ids = Array(people_ids)
    @today = today
  end

  def hero
    @hero ||= on_its_way_hero || approved_hero || waiting_hero || caught_up_hero
  end

  # Approved and waiting money, shown under an "on its way" hero.
  def still_to_be_paid_cents
    queued_items.sum(&:amount_cents) + unbatched_cents(approved_entries) + unbatched_cents(waiting_entries)
  end

  def days
    @days ||= begin
      tipped = {}
      recent_entries.first(DAYS).map do |entry|
        # Two stints on one date share that date's tips: the first carries them.
        key = [ entry.payout_batch_id, entry.started_at.to_date ]
        tips = entry.payout_batch_id && !tipped[key] ? tips_by_day[key].to_i : 0
        tipped[key] = true
        day_for(entry, tips)
      end
    end
  end

  private

  # --- The big number -----------------------------------------------------

  def on_its_way_hero
    sent = items.select { |i| i.deposit_stage(@today) == :on_its_way }
    going = items.select { |i| i.status == "pending" && i.payout_batch.in_flight? }
    return nil if sent.empty? && going.empty?

    expected = (sent.map(&:expected_deposit_date) + going.map { |i| i.payout_batch.expected_deposit_range.first }).compact.min
    build_hero(:on_its_way, cents: (sent + going).sum(&:amount_cents), on: expected, items: sent + going,
                      sent_on: sent.map { |i| i.paid_at.to_date }.min)
  end

  def approved_hero
    cents = queued_items.sum(&:amount_cents) + unbatched_cents(approved_entries)
    return nil unless cents.positive?

    build_hero(:approved, cents: cents, on: queued_items.filter_map { |i| i.payout_batch.payday }.min, items: queued_items)
  end

  def waiting_hero
    return nil if waiting_entries.empty?

    build_hero(:waiting, cents: unbatched_cents(waiting_entries), on: nil, items: [],
                   hours: waiting_entries.sum { |e| e.hours.to_d })
  end

  def caught_up_hero
    last = items.select(&:paid?).max_by(&:paid_at)
    return nil unless last

    deposited = last.deposit_stage(@today) == :deposited
    build_hero(:caught_up, cents: last.amount_cents, on: deposited ? last.deposited_at.to_date : last.paid_at.to_date,
                     items: [ last ], settled_as: deposited ? :deposited : :sent)
  end

  def build_hero(stage, cents:, on:, items:, sent_on: nil, hours: nil, settled_as: nil)
    orgs = items.filter_map { |i| i.payout_batch.organization&.name }.uniq
    orgs = waiting_entries.filter_map { |e| e.organization&.name }.uniq if orgs.empty? && stage == :waiting
    Hero.new(stage: stage, cents: cents, on: on, org: orgs.to_sentence.presence, sent_on: sent_on, hours: hours,
             settled_as: settled_as)
  end

  # --- Each day -----------------------------------------------------------

  def day_for(entry, tips_cents = 0)
    stage, on =
      if entry.offline_paid_at
        [ :paid_directly, entry.offline_paid_at.to_date ]
      elsif entry.payout_batch_id
        batched_stage(entry)
      elsif entry.approved_at
        [ :approved, nil ]
      else
        [ :waiting, nil ]
      end
    cents = entry.offline_paid_at ? (entry.offline_total_cents || price(entry)) : price(entry)
    Day.new(date: entry.started_at.to_date, hours: entry.hours.to_d, cents: cents + tips_cents, tips_cents: tips_cents,
            stage: stage, on: on)
  end

  # Hours in a payout run: where the person's payment in that run stands.
  def batched_stage(entry)
    item = items.find { |i| i.payout_batch_id == entry.payout_batch_id && i.payee_id == entry.person_id }
    return [ :approved, nil ] unless item

    case item.deposit_stage(@today)
    when :deposited then [ :deposited, item.deposited_at.to_date ]
    when :on_its_way then [ :on_its_way, item.expected_deposit_date ]
    when :sent then [ :sent, item.paid_at.to_date ]
    else
      batch = item.payout_batch
      batch.in_flight? ? [ :on_its_way, batch.expected_deposit_range.first ] : [ :approved, batch.payday ]
    end
  end

  # --- What it's made of --------------------------------------------------

  def items
    @items ||= PayoutBatchItem.where(payee_type: "Person", payee_id: @people_ids, status: %w[pending paid failed])
                              .includes(payout_batch: :organization).to_a
                              .select { |i| i.paid? || PayoutBatchService::UNSETTLED_BATCH_STATUSES.include?(i.payout_batch.status) }
  end

  # Card tips each run pays, by [run, date], from the Tips line's per-day
  # worksheet. A Tips line typed as one total with no worksheet goes on the
  # day when the run holds only one of this person's days; otherwise it isn't
  # any one day's.
  def tips_by_day
    @tips_by_day ||= begin
      by_day = Hash.new(0)
      dates_by_run = entries.select(&:payout_batch_id).group_by(&:payout_batch_id)
                            .transform_values { |list| list.map { |e| e.started_at.to_date }.uniq }
      PayoutContribution.where(payout_batch_item_id: items.map(&:id), label: "Tips", excluded_from_payout: false).find_each do |tips|
        dated = tips.worksheet_entries.filter_map do |row|
          [ Date.parse(row["date"].to_s), row["amount_cents"].to_i ]
        rescue Date::Error
          nil
        end
        if dated.any?
          dated.each { |date, cents| by_day[[ tips.payout_batch_id, date ]] += cents }
        elsif (dates = dates_by_run[tips.payout_batch_id]) && dates.one?
          by_day[[ tips.payout_batch_id, dates.first ]] += tips.amount_cents
        end
      end
      by_day
    end
  end

  # In a payout run that hasn't gone out yet.
  def queued_items
    @queued_items ||= items.select { |i| !i.paid? && !i.payout_batch.in_flight? }
  end

  def entries
    @entries ||= StaffTimeEntry.where(person_id: @people_ids)
                               .where("staff_time_entries.payout_batch_id IS NULL AND staff_time_entries.offline_paid_at IS NULL " \
                                      "OR staff_time_entries.started_at >= ?", RECENT.ago)
                               .includes(:organization, :house_role, shift_assignment: { shift: :house_role })
                               .order(started_at: :desc).to_a
  end

  def recent_entries = entries

  def approved_entries = entries.select { |e| e.payout_batch_id.nil? && e.offline_paid_at.nil? && e.approved_at }
  def waiting_entries = entries.select { |e| e.payout_batch_id.nil? && e.offline_paid_at.nil? && e.approved_at.nil? }

  def unbatched_cents(list) = list.sum { |e| price(e) }

  # Each entry at the role it was worked as (the member's default rate is only
  # the fallback for role-less time).
  def price(entry)
    member = members[[ entry.organization_id, entry.person_id ]]
    member ? member.amount_cents_for(entry.effective_house_role, hours: entry.hours) : 0
  end

  def members
    @members ||= OrganizationStaffMember.where(person_id: @people_ids)
                                        .includes(staff_role_qualifications: :house_role)
                                        .index_by { |m| [ m.organization_id, m.person_id ] }
  end
end
