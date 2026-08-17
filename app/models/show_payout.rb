# frozen_string_literal: true

class ShowPayout < ApplicationRecord
  # Only two actual statuses: awaiting_payout (calculated, not all paid) and paid (all paid)
  STATUSES = %w[awaiting_payout paid].freeze

  belongs_to :show
  belongs_to :payout_scheme, optional: true

  has_one :production, through: :show
  has_one :show_financials, through: :show

  has_many :line_items, class_name: "ShowPayoutLineItem", dependent: :destroy

  validates :show_id, uniqueness: true
  validates :status, inclusion: { in: STATUSES }, allow_nil: true

  # Migrate legacy statuses (draft, approved, etc.) to awaiting_payout
  before_validation :normalize_status

  scope :awaiting_payout, -> { where(status: "awaiting_payout") }
  scope :paid, -> { where(status: "paid") }
  scope :not_paid, -> { where.not(status: "paid") }

  # A payout pins its scheme the first time its page is opened. When the
  # production's scheme changes, payouts nobody has calculated yet (no line
  # items, no hand-tuned override) should follow it rather than keep the
  # scheme that happened to resolve on the day the page was first viewed.
  # `scheme` nil means "resolve the default again for each show". `from` limits
  # it to shows on or after that date (a dated switch of scheme).
  def self.restamp_pending_for_production!(production, scheme, from: nil)
    shows = production.shows
    shows = shows.where("shows.date_and_time >= ?", from.to_date.beginning_of_day) if from.present?
    where(show_id: shows.select(:id), calculated_at: nil)
      .where.missing(:line_items)
      .where("override_rules IS NULL OR override_rules = '{}'::jsonb")
      .includes(:show)
      .find_each do |payout|
        payout.update!(payout_scheme: scheme || PayoutScheme.default_for_show(payout.show))
      end
  end

  # Get effective rules (override or scheme)
  def effective_rules
    override_rules.presence || payout_scheme&.rules || {}
  end

  # Check if using event-level overrides
  def has_overrides?
    override_rules.present?
  end

  # The calculation this event's customization started from: this payout's own
  # calculation, or the default for the show when none is pinned.
  def base_scheme
    payout_scheme || PayoutScheme.default_for_show(show)
  end

  def base_rules
    (base_scheme&.rules || {}).deep_stringify_keys
  end

  # Whether the calculation this event starts from splits a fixed pot of the
  # night's money (equal / shares). Customized amounts for such a night have to
  # add back up to that pot — there's no more and no less to hand out.
  def fixed_pot?
    PayoutRulesBuilder.pool_method?(base_rules.dig("distribution", "method"))
  end

  # One line saying what this event's customization changed against the
  # calculation it started from — "Everyone $60", "Jane Doe $100, Gigi (guest)
  # $40", or for older customizations "House 30% instead of 40%". nil when
  # there is no customization. Falls back to "Custom amounts" when the override
  # differs in some way this can't put into words.
  def customization_summary
    return nil unless has_overrides?

    override = override_rules.deep_stringify_keys
    return "Closed as non-paying" if override["closed_as_non_paying"]

    base = base_rules
    people = person_amount_changes(override)
    # "Pay everyone the same amount": one flat amount, nobody named.
    if override.dig("distribution", "method").to_s == "flat_fee" && people.blank?
      return "Everyone #{money(override.dig('distribution', 'flat_amount'))}"
    end

    parts = []
    parts.concat(method_and_amount_changes(base, override))
    # A swapped approach (legacy override) says it all; house/expenses only
    # mean something within the same approach.
    parts.concat(pool_changes(base, override)) unless method_changed?(base, override)
    parts << people if people.present?

    parts.presence&.join("; ") || "Custom amounts"
  end

  # --- What each payee stands to be paid ------------------------------------
  #
  # The Customize modal prefills every payee's amount with what they'd get right
  # now, and checks customized amounts against what the calculation itself would
  # give. All keyed like `act_key` ("Person_12", "Group_3", "guest_45").

  # What each payee would be paid as things stand: the calculated line items
  # once the payout has been calculated, otherwise a dry run of the calculation
  # this event currently resolves to (customization included).
  def current_amounts
    return amounts_from_line_items(line_items.to_a) if calculated_at.present? && line_items.exists?

    preview_amounts
  end

  # What the calculation itself gives each payee, before any customization —
  # the numbers a customization is measured against.
  def calculated_amounts
    has_overrides? ? preview_amounts(base_rules) : current_amounts
  end

  # The calculation's total for the people cast on this show, or nil when it
  # can't be worked out yet (no financials, nobody cast).
  def calculated_total
    amounts = calculated_amounts
    return nil if amounts.empty?

    act_payees.sum { |payee| amounts[self.class.act_key(payee)].to_f }.round(2)
  end

  # Dry run of the calculation: the numbers PayoutCalculator would persist,
  # without persisting anything (no line items, no ledger, no calculated_at).
  # Empty when it can't run yet. Memoized per rules + act counts, since a page
  # asks for the same dry run more than once.
  def preview_amounts(rules = resolved_rules)
    return {} if rules.blank?

    act_counts = preview_act_counts
    @preview_amounts ||= {}
    @preview_amounts[[ rules, act_counts ]] ||= begin
      result = PayoutCalculator.calculate(show: show, rules: rules, act_counts: act_counts, persist: false)
      result[:success] ? amounts_from_line_items(result[:line_items]) : {}
    end
  end

  # The exact amount this event's customization names for a payee, if any —
  # keyed like `act_key`; an older customization keyed a person by bare id.
  def override_amount_for(payee)
    overrides = (override_rules || {}).deep_stringify_keys["performer_overrides"] || {}
    override = overrides[self.class.act_key(payee)]
    override = overrides[payee.id.to_s] if override.nil? && payee.is_a?(Person)
    amount = override.is_a?(Hash) ? override["flat_amount"] : nil
    amount.presence&.to_f
  end

  def reload(*)
    @preview_amounts = nil
    super
  end

  # --- Act-based pay -------------------------------------------------------
  #
  # An act-based scheme can't be calculated from the show's data alone: someone
  # has to say how many acts each person did. Those counts live here (keyed by
  # payee) so they survive the line items being rebuilt on every recalculation.

  # The rules a calculation would actually run on: an event-level override, this
  # payout's scheme, or — when neither is set — the default scheme for the show.
  def resolved_rules
    override_rules.presence || (payout_scheme || PayoutScheme.default_for_show(show))&.rules || {}
  end

  def act_based?
    resolved_rules.dig("distribution", "method").to_s == "per_act"
  end

  # Stable key for one payee's act count: a cast member ("Person_12" /
  # "Group_3"), or a guest slot on the show ("guest_45", keyed by the
  # assignment because a guest has no record of their own).
  def self.act_key(payee)
    return "guest_#{payee.id}" if payee.is_a?(ShowPersonRoleAssignment)

    "#{payee.class.name}_#{payee.id}"
  end

  # The distribution config an act-based calculation runs on (rate, schedule or
  # tiers), and the same rules spelled out for the person entering act counts.
  def act_distribution
    resolved_rules["distribution"] || {}
  end

  def act_rules_description
    PayoutScheme.act_rules_description(act_distribution)
  end

  def act_count_for(payee)
    (act_counts || {})[self.class.act_key(payee)].to_i
  end

  # The payees an act-based calculation needs a count for: everyone assigned to
  # the show.
  def act_payees
    cast = show.pay_cast_assignments
    cast[:people] + cast[:guests]
  end

  # In an act-based production the lineup already says how many acts each
  # person holds — no one needs to type it in.
  def counts_acts_from_lineup?
    show.act_based?
  end

  # Status helpers
  def awaiting_payout?
    status == "awaiting_payout"
  end

  def paid?
    status == "paid"
  end

  # Derived statuses based on show financials state
  def awaiting_financials?
    !show.show_financials&.complete?
  end

  def awaiting_calculation?
    show.show_financials&.complete? && !calculated_at.present?
  end

  def can_edit?
    !paid?
  end

  def can_recalculate?
    !paid? && show.show_financials&.complete?
  end

  # Mark as paid (when all line items are paid)
  def mark_paid!
    update!(status: "paid")
    settle_contract_payment!
  end

  # Auto-settle the ContractPayment associated with this show, if one exists.
  # For per-event contracts: always settle. For weekly/monthly: only settle when
  # all shows in the period have been paid.
  def settle_contract_payment!(payment_method: nil, notes: nil)
    production = show.production
    return unless production.type_third_party?

    # A production can carry several contracts; the one that applies to THIS show is
    # the one that booked its space rental. Fall back to the production's latest.
    contract = show.space_rental&.contract || production.contract
    return unless contract&.revenue_share?

    contract_payment = contract.find_payment_for_show(show)
    return unless contract_payment&.status_pending?

    settlement = contract.draft_payment_config["revenue_settlement"] || "monthly"
    if %w[per_event next_day same_day].include?(settlement)
      contract_payment.mark_paid!(paid_on: Date.current, method: payment_method, reference: notes)
    else
      # For period-based settlements, only settle once all shows in the period are paid
      period_shows = contract.shows_for_payment(contract_payment)
      all_paid = period_shows.all? do |s|
        s.show_payout&.paid?
      end
      if all_paid
        contract_payment.mark_paid!(paid_on: Date.current, method: payment_method, reference: notes)
      end
    end
  rescue => e
    Rails.logger.warn("Could not settle contract payment for show #{show.id}: #{e.message}")
  end

  # Mark as awaiting payout (when calculated)
  def mark_awaiting_payout!
    update!(status: "awaiting_payout")
  end

  # Revert from paid to awaiting_payout (when unmarking a line item)
  def revert_to_awaiting_payout!
    return false unless paid?
    update!(status: "awaiting_payout")
  end

  # Calculate total from line items
  def recalculate_total!
    update!(total_payout: line_items.sum(:amount))
  end

  # Whether any of this show's payout lines have already been added to a
  # (performer) payout run.
  def in_payout_run?
    PayoutContribution.where(source_type: "ShowPayoutLineItem", source_id: line_items.select(:id)).exists?
  end

  # The specific (performer) payout run this show's payouts were added to, if any,
  # so we can link straight to it instead of the full list of runs.
  def payout_run
    PayoutContribution
      .where(source_type: "ShowPayoutLineItem", source_id: line_items.select(:id))
      .order(created_at: :desc)
      .first&.payout_batch
  end

  # Post/refresh each performer line item's `earning` entry on the payout ledger.
  # Idempotent (keyed per line item); called after a payout is calculated and by
  # the ledger backfill. Paid line items also carry an offsetting `payout` entry.
  def sync_earnings_to_ledger!
    line_items.includes(:payee).find_each do |li|
      li.sync_earning_ledger_entry!
      li.sync_payout_ledger_entry! if li.paid?
    end
  end

  # Total advance deductions from all line items
  def total_advance_deductions
    line_items.sum(:advance_deduction)
  end

  # Net total (what actually needs to be paid out)
  def total_net_payout
    (total_payout || 0) - total_advance_deductions
  end

  # Check if advance deductions are stale (out of sync with current advance state)
  # Returns true if:
  # 1. Line items show deductions but those advances are now settled (already recovered)
  # 2. There are outstanding advances for performers that aren't reflected in deductions
  # Advances are no longer deducted at calc time (they net on the payout ledger),
  # so there's nothing to be "stale" against.
  def advance_deductions_stale?
    false
  end

  # Display status - combines stored status with derived states
  def display_status
    return :paid if paid?
    return :awaiting_payout if awaiting_payout? || calculated_at.present?
    return :awaiting_calculation if awaiting_calculation?
    :awaiting_financials
  end

  def display_status_label
    case display_status
    when :awaiting_financials then "Awaiting Financials"
    when :awaiting_calculation then "Awaiting Calculation"
    when :awaiting_payout then "Awaiting Payout"
    when :paid then "Paid"
    end
  end

  def display_status_class
    case display_status
    when :awaiting_financials then "text-pink-600"
    when :awaiting_calculation then "text-gray-600"
    when :awaiting_payout then "text-pink-600"
    when :paid then "text-pink-600"
    end
  end

  private

  # Normalize legacy statuses (draft, approved, etc.) to valid statuses
  def normalize_status
    return if status.nil? || STATUSES.include?(status)

    # Any non-paid legacy status becomes awaiting_payout
    self.status = "awaiting_payout"
  end

  # --- current / preview amounts helpers -------------------------------------

  # Lines → { act_key => amount } for the payees on this show. Takes saved
  # ShowPayoutLineItems or the hashes a dry run returns. Someone's cut off the
  # top (an individual allocation) isn't a payee amount. A guest line is keyed
  # by the guest slot it was paid for (two guests can share a name); a line
  # saved before that was recorded falls back to matching the name.
  def amounts_from_line_items(items)
    guests = act_payees.select { |p| p.is_a?(ShowPersonRoleAssignment) }
    guest_ids = guests.map(&:id).to_set
    guests_by_name = guests.reverse.index_by(&:guest_name) # first slot with the name wins

    items.each_with_object({}) do |item, amounts|
      line = item.is_a?(ShowPayoutLineItem) ? line_item_fields(item) : item
      next if line[:is_individual_allocation]

      key = if line[:is_guest]
        guest_id = line[:guest_assignment_id].to_i
        guest_id = guests_by_name[line[:guest_name]]&.id unless guest_ids.include?(guest_id)
        guest_id && "guest_#{guest_id}"
      elsif line[:payee]
        self.class.act_key(line[:payee])
      end
      amounts[key] = line[:amount].to_f if key
    end
  end

  # A saved line item as the hash a dry run would have returned for it.
  def line_item_fields(item)
    details = item.calculation_details.is_a?(Hash) ? item.calculation_details : {}
    {
      payee: item.payee,
      is_guest: item.is_guest?,
      guest_name: item.guest_name,
      guest_assignment_id: details["guest_assignment_id"],
      is_individual_allocation: item.is_individual_allocation?,
      amount: item.amount
    }
  end

  # The act counts a dry run should use — what `calculate` would: the lineup
  # in an act-based production, otherwise whatever was entered by hand.
  def preview_act_counts
    show.act_based? ? show.lineup_act_counts : (act_counts || {})
  end

  # --- customization_summary helpers ----------------------------------------

  METHOD_LABELS = {
    "no_pay" => "Not paid", "flat_fee" => "Flat amount each", "per_act" => "Paid by acts",
    "per_ticket" => "Per ticket", "per_ticket_guaranteed" => "Per ticket with a minimum",
    "equal" => "Split equally", "shares" => "Split by shares"
  }.freeze

  def method_changed?(base, override)
    from_method = base.dig("distribution", "method").to_s
    from_method.present? && from_method != override.dig("distribution", "method").to_s
  end

  def method_and_amount_changes(base, override)
    from = base["distribution"] || {}
    to = override["distribution"] || {}
    from_method = from["method"].to_s
    to_method = to["method"].to_s
    changes = []

    if method_changed?(base, override)
      changes << "#{METHOD_LABELS.fetch(to_method, to_method.humanize)} instead of #{METHOD_LABELS.fetch(from_method, from_method.humanize).downcase}"
      return changes
    end

    case to_method
    when "flat_fee"
      changes << "Flat #{money(to['flat_amount'])} instead of #{money(from['flat_amount'])}" if differs?(from["flat_amount"], to["flat_amount"])
    when "per_ticket", "per_ticket_guaranteed"
      changes << "#{money(to['per_ticket_rate'])}/ticket instead of #{money(from['per_ticket_rate'])}" if differs?(from["per_ticket_rate"], to["per_ticket_rate"])
      changes << "Minimum #{money(to['minimum'])} instead of #{money(from['minimum'])}" if to_method == "per_ticket_guaranteed" && differs?(from["minimum"], to["minimum"])
    when "shares"
      changes << "#{number(to['default_shares'])} shares each instead of #{number(from['default_shares'])}" if differs?(from["default_shares"], to["default_shares"])
    when "per_act"
      from_desc = PayoutScheme.act_rules_description(from)
      to_desc = PayoutScheme.act_rules_description(to)
      changes << "#{to_desc} instead of #{from_desc}" if from_desc != to_desc
    end

    changes
  end

  # House take and expenses-first for the pool methods.
  def pool_changes(base, override)
    changes = []
    from_house = house_percentage(base)
    to_house = house_percentage(override)
    changes << "House #{number(to_house)}% instead of #{number(from_house)}%" if differs?(from_house, to_house)

    from_expenses = expenses_first?(base)
    to_expenses = expenses_first?(override)
    if from_expenses != to_expenses
      changes << (to_expenses ? "Expenses covered first" : "Expenses no longer covered first")
    end
    changes
  end

  # "Jane Doe $100, Gigi (guest) $40" for every exact per-person amount.
  def person_amount_changes(override)
    overrides = override["performer_overrides"] || {}
    return "" if overrides.blank?

    # In cast order (jsonb doesn't keep the order the keys were written in);
    # anyone no longer cast comes last.
    cast = act_payees.index_by { |p| self.class.act_key(p) }
    order = cast.keys.each_with_index.to_h
    named = overrides.filter_map do |key, data|
      amount = data.is_a?(Hash) ? data["flat_amount"] : nil
      next if amount.blank?

      legacy_key = key.to_s.match?(/\A\d+\z/) ? "Person_#{key}" : key.to_s
      [ order.fetch(legacy_key, order.size), "#{override_payee_name(key, cast)} #{money(amount)}" ]
    end
    named.sort_by.with_index { |(position, _), index| [ position, index ] }.map(&:last).join(", ")
  end

  # Who a performer_overrides key names: "guest_45" is a guest slot on this
  # show, "Person_12" / "Group_3" someone cast on it or one of the org's own
  # people or groups. An older customization keyed a person by bare id ("12").
  # Never a bare Person.find_by — the lookup stays within the show's org.
  def override_payee_name(key, cast = act_payees.index_by { |p| self.class.act_key(p) })
    key = key.to_s
    organization = show.production.organization

    if key.start_with?("guest_")
      assignment = cast[key] || show.show_person_role_assignments.find_by(id: key.delete_prefix("guest_"))
      "#{assignment&.guest_name.presence || 'Guest'} (guest)"
    elsif key.start_with?("Group_")
      id = key.delete_prefix("Group_")
      (cast[key] || organization.groups.find_by(id: id))&.name || "Group ##{id}"
    else
      id = key.delete_prefix("Person_")
      (cast["Person_#{id}"] || organization.people.find_by(id: id))&.name || "Person ##{id}"
    end
  end

  def house_percentage(rules)
    step = Array(rules["allocation"]).find { |s| s["type"] == "percentage" && s["person_id"].blank? }
    step ? step["value"].to_f : 0.0
  end

  def expenses_first?(rules)
    Array(rules["allocation"]).any? { |s| s["type"] == "expenses_first" }
  end

  def differs?(from, to)
    from.to_f.round(4) != to.to_f.round(4)
  end

  def money(amount)
    "$#{'%.2f' % amount.to_f}".delete_suffix(".00")
  end

  def number(value)
    f = value.to_f
    f == f.to_i ? f.to_i.to_s : f.to_s
  end
end
