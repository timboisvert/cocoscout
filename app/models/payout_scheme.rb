# frozen_string_literal: true

# A payout calculation — shown to users as "payout calculation" everywhere; the
# class and table keep their original name. Its `rules` jsonb (allocation +
# distribution + performer_overrides, built by PayoutRulesBuilder) is what
# PayoutCalculator runs for a show. Created/edited through
# Manage::PayoutCalculationWizardController.
class PayoutScheme < ApplicationRecord
  belongs_to :organization, optional: true
  belongs_to :production, optional: true

  has_many :show_payouts, dependent: :nullify
  has_many :payout_scheme_defaults, dependent: :destroy

  validates :name, presence: true
  validates :rules, presence: true
  validate :must_have_organization_or_production
  validates :name, uniqueness: { scope: :organization_id }, if: -> { organization_id.present? && production_id.blank? }
  validates :name, uniqueness: { scope: :production_id }, if: -> { production_id.present? }

  scope :organization_level, -> { where(production_id: nil) }
  scope :production_level, -> { where.not(production_id: nil) }
  scope :for_organization, ->(org) { where(organization: org) }
  scope :effective_on, ->(date) { where("payout_schemes.effective_from IS NULL OR payout_schemes.effective_from <= ?", date) }
  scope :archived, -> { where.not(archived_at: nil) }
  scope :active, -> { where(archived_at: nil) }

  def archived?
    archived_at.present?
  end

  def archive!
    update!(archived_at: Time.current)
  end

  def unarchive!
    update!(archived_at: nil)
  end

  # The calculation a show starts from: the one its production chose (the row
  # in effect on the show's date). There is no organization-level fallback —
  # a production that hasn't chosen one has none, and a production whose
  # performer pay is switched off resolves to none even if it kept its rows.
  def self.default_for_show(show)
    return nil unless show.production&.pays_performers?

    show_date = show.date_and_time&.to_date || Date.current
    PayoutSchemeDefault
      .for_production(show.production)
      .effective_on(show_date)
      .by_effective_date_desc
      .first
      &.payout_scheme
  end

  # The calculation this production has chosen as of a date (nil if none, or
  # if the production doesn't pay performers — pass include_paused: true to
  # see the one it keeps while pay is switched off, e.g. on the Pay tab).
  def self.current_default_for_production(production, on: Date.current, include_paused: false)
    return nil unless production && (include_paused || production.pays_performers?)

    PayoutSchemeDefault
      .for_production(production)
      .effective_on(on)
      .by_effective_date_desc
      .first
      &.payout_scheme
  end

  # The same answer for many productions in one query: { production_id =>
  # PayoutScheme or nil }, the row in effect on `on` picked in Ruby.
  def self.current_defaults_for_productions(productions, on: Date.current)
    productions = Array(productions)
    rows = PayoutSchemeDefault.where(production_id: productions.map(&:id))
                              .includes(:payout_scheme)
                              .group_by(&:production_id)
    productions.to_h do |production|
      next [ production.id, nil ] unless production.pays_performers?

      row = PayoutSchemeDefault.in_effect_on(rows[production.id] || [], on)
      [ production.id, row&.payout_scheme ]
    end
  end

  # Does the org have any (non-archived) scheme that pays by acts?
  def self.per_act_scheme_exists_for?(organization)
    organization.payout_schemes.active.any?(&:act_based?)
  end

  private

  def must_have_organization_or_production
    if organization_id.blank? && production_id.blank?
      errors.add(:base, "must belong to either an organization or a production")
    end
  end

  public

  # Add a production to this scheme's defaults (keeps existing)
  def add_default_for_production!(production, effective_from: nil)
    # Clear any conflicting default for this production/date
    PayoutSchemeDefault
      .where(production_id: production.id, effective_from: effective_from)
      .destroy_all

    payout_scheme_defaults.find_or_create_by!(
      production_id: production.id,
      effective_from: effective_from
    )
  end

  # Make this THE scheme for a production — the answer to "which payout
  # calculation does this production use?" asked from the production wizard,
  # the Pay tab, the "used by" modal or the calculation wizard.
  #
  # With no starting_on it takes over from now on: whatever the production
  # used before today stays on record for the shows before it (its history and
  # any other calculation's earlier-dated rows are kept), any switch dated
  # today or later — including this calculation's own rows — is replaced by
  # one row. If that leaves the production with no history at all, the row
  # reaches back to the production's earliest show, so nights already on the
  # calendar resolve to it too; otherwise it's dated today. Then it restamps
  # show payouts that haven't been worked out yet from that date on, because a
  # payout pins its calculation the first time its page is opened.
  #
  # With a starting_on date the switch is dated: whatever the production used
  # before that date stays in place for the shows before it; only rows dated
  # on or after starting_on are replaced, and only pending payouts for shows
  # on or after it are restamped.
  def make_production_scheme!(production, starting_on: nil)
    transaction do
      rows = PayoutSchemeDefault.for_production(production)
      if starting_on.present?
        starting_on = starting_on.to_date
        rows.where("effective_from >= ?", starting_on).destroy_all
        effective_from = starting_on
      else
        rows.where("effective_from >= ?", Date.current).or(rows.where(payout_scheme_id: id)).destroy_all
        effective_from = rows.exists? ? Date.current : self.class.production_scheme_start(production)
      end
      payout_scheme_defaults.create!(production_id: production.id, effective_from: effective_from)
      ShowPayout.restamp_pending_for_production!(production, self, from: effective_from)
    end
  end

  # This calculation stops covering a production (it was unchecked on the
  # "who uses it" list): only ITS rows for the production go — another
  # calculation's history and scheduled switches stay. Payouts nobody has
  # calculated yet follow whatever the production resolves to now (which may
  # be nothing).
  def stop_covering!(production)
    transaction do
      payout_scheme_defaults.where(production_id: production.id).destroy_all
      ShowPayout.restamp_pending_for_production!(production, nil)
    end
  end

  # Drop every calculation the production has, any date — its shows have none
  # until another is chosen. Reserved for deliberate wipes; the performer-pay
  # switch keeps the rows and only flips Production#pays_performers.
  def self.clear_production_scheme!(production)
    transaction do
      PayoutSchemeDefault.for_production(production).destroy_all
      ShowPayout.restamp_pending_for_production!(production, nil)
    end
  end

  # The date a production-wide scheme takes effect: its first show, or today
  # if it has none / they're all ahead.
  def self.production_scheme_start(production)
    first_show = production.shows.minimum(:date_and_time)&.to_date
    [ first_show, Date.current ].compact.min
  end

  # Check if this scheme is default for a given production (at any date)
  def default_for_production?(production)
    payout_scheme_defaults.where(production_id: production.id).exists?
  end

  # Get allocation steps
  def allocation_steps
    rules.dig("allocation") || []
  end

  # Get distribution config
  def distribution_config
    rules.dig("distribution") || {}
  end

  # Get performer overrides
  def performer_overrides
    rules.dig("performer_overrides") || {}
  end

  # Get distribution method
  def distribution_method
    distribution_config["method"] || "equal"
  end

  # --- Act-based pay -------------------------------------------------------
  #
  # Some shows pay by how many acts a person did on the night rather than by
  # ticket sales or an even split. Rooms word that three different ways, so
  # "per_act" carries an act_mode saying which one this scheme means:
  #
  #   simple   — every act is worth the same ($25/act, so two acts pays $50)
  #   tiers    — a table by how many acts they did, each row the TOTAL for
  #              that many acts: 1 act pays $75, 2 acts pays $125. Past the
  #              last row, every further act adds additional_act_rate (blank
  #              means the last row is the ceiling).
  #   schedule — legacy: each act worth its own amount and they add up (the
  #              first act $75, the second $50, then the "additional" rate).
  #              Still calculated for stored rules; the wizard no longer
  #              offers it — a tiers table says the same thing.
  #
  # The act counts themselves aren't part of the scheme — they're entered per
  # show at calculation time and stored on ShowPayout#act_counts.
  ACT_MODES = %w[simple schedule tiers].freeze

  def act_based?
    distribution_method == "per_act"
  end

  # What a payee earns for `act_count` acts under the given distribution config.
  # Takes the raw distribution hash (not a scheme) because a show can override
  # its scheme's rules without a PayoutScheme record existing for them.
  def self.act_amount(distribution, act_count)
    distribution = (distribution || {}).deep_stringify_keys
    count = act_count.to_i
    return 0.0 if count <= 0

    case distribution["act_mode"].to_s
    when "simple"
      (distribution["per_act_rate"].to_f * count).round(2)
    when "schedule"
      rates = act_rates(distribution)
      tail = additional_act_rate(distribution)
      (1..count).sum { |n| rates[n - 1] ? rates[n - 1]["amount"].to_f : tail }.round(2)
    else
      tiers = act_tiers(distribution)
      tier = tiers.select { |t| t["acts"].to_i <= count }.last
      return 0.0 unless tier

      amount = tier["amount"].to_f
      # Past the last row, each further act adds the beyond rate (if any).
      if tier.equal?(tiers.last) && count > tier["acts"].to_i && distribution["additional_act_rate"].present?
        amount += additional_act_rate(distribution) * (count - tier["acts"].to_i)
      end
      amount.round(2)
    end
  end

  # Tier rows ("this many acts pays this total"), sorted by act count ascending.
  def self.act_tiers(distribution)
    tiers = (distribution || {}).deep_stringify_keys["tiers"]
    Array(tiers)
      .map { |t| t.deep_stringify_keys }
      .select { |t| t["acts"].to_i > 0 }
      .sort_by { |t| t["acts"].to_i }
  end

  # Schedule rows ("the Nth act is worth this much"), in act order. The rows are
  # positional, so a bare list of amounts is accepted and numbered by position.
  def self.act_rates(distribution)
    rows = (distribution || {}).deep_stringify_keys["act_rates"]
    Array(rows)
      .each_with_index
      .map do |row, index|
        row = { "amount" => row } unless row.is_a?(Hash)
        { "act" => (row["act"].presence || index + 1).to_i, "amount" => row["amount"].to_f }
      end
      .sort_by { |row| row["act"] }
  end

  # What every act past the end of the schedule / the last tier row is worth.
  # Blank means those acts add nothing, which is a real choice ("we only pay
  # for two").
  def self.additional_act_rate(distribution)
    (distribution || {}).deep_stringify_keys["additional_act_rate"].to_f
  end

  # "$25.00 per act" / "1 act $75.00, 2 acts $125.00, then $50.00 per act" /
  # "1 act $25.00, 2+ acts $50.00" (no beyond rate) / legacy schedule "1st act
  # $75.00, 2nd act $50.00, then $50.00 each"
  def self.act_rules_description(distribution)
    distribution = (distribution || {}).deep_stringify_keys

    case distribution["act_mode"].to_s
    when "simple"
      "#{act_money(distribution['per_act_rate'])} per act"
    when "schedule"
      rows = act_rates(distribution)
      return "No act rates set" if rows.empty?

      parts = rows.map { |row| "#{row['act'].ordinalize} act #{act_money(row['amount'])}" }
      parts << "then #{act_money(distribution['additional_act_rate'])} each" if distribution["additional_act_rate"].present?
      parts.join(", ")
    else
      rows = act_tiers(distribution)
      return "No act tiers set" if rows.empty?

      beyond = distribution["additional_act_rate"].present?
      parts = rows.each_with_index.map do |tier, index|
        acts = tier["acts"].to_i
        last = index == rows.length - 1
        label = last && !beyond ? "#{acts}+ acts" : "#{acts} #{'act'.pluralize(acts)}"
        "#{label} #{act_money(tier['amount'])}"
      end
      parts << "then #{act_money(distribution['additional_act_rate'])} per act" if beyond
      parts.join(", ")
    end
  end

  def self.act_money(amount)
    "$#{'%.2f' % amount.to_f}"
  end

  # A name for a calculation nobody has named yet, read off its rules — what
  # the wizard offers on the review step. Short, the way you'd say it out
  # loud: "$25 per act", "$50 flat per performer", "Even split after 40% house".
  def self.suggested_name(rules)
    rules = (rules || {}).deep_stringify_keys
    dist = rules["distribution"] || {}
    # "$25", "$2.50" — whole dollars lose the cents, anything else keeps two.
    money = ->(amount) { amount.to_f == amount.to_f.to_i ? "$#{amount.to_f.to_i}" : "$#{'%.2f' % amount.to_f}" }
    percent = ->(value) { ActiveSupport::NumberHelper.number_to_rounded(value.to_f, strip_insignificant_zeros: true, precision: 2) }

    case dist["method"].to_s
    when "flat_fee"
      "#{money.call(dist['flat_amount'])} flat per performer"
    when "per_ticket"
      "#{money.call(dist['per_ticket_rate'])}/ticket"
    when "per_ticket_guaranteed"
      "#{money.call(dist['per_ticket_rate'])}/ticket, min #{money.call(dist['minimum'])}"
    when "per_act"
      case dist["act_mode"].to_s
      when "simple"
        "#{money.call(dist['per_act_rate'])} per act"
      when "schedule"
        rows = act_rates(dist)
        parts = rows.map { |row| "#{row['act'].ordinalize} act #{money.call(row['amount'])}" }
        parts << "then #{money.call(dist['additional_act_rate'])} each" if dist["additional_act_rate"].present?
        parts.presence&.join(", ") || "Paid by acts"
      else
        rows = act_tiers(dist)
        parts = rows.map { |tier| "#{tier['acts']} #{'act'.pluralize(tier['acts'].to_i)} #{money.call(tier['amount'])}" }
        parts << "then #{money.call(dist['additional_act_rate'])} each" if dist["additional_act_rate"].present?
        parts.presence&.join(", ") || "Paid by acts"
      end
    when "shares"
      "Split by shares"
    when "no_pay"
      "Not paid"
    else
      house = Array(rules["allocation"]).find { |s| s["type"] == "percentage" && s["person_id"].blank? }
      house && house["value"].to_f.positive? ? "Even split after #{percent.call(house['value'])}% house" : "Even split"
    end
  end

  def act_tiers
    self.class.act_tiers(distribution_config)
  end

  def act_rates
    self.class.act_rates(distribution_config)
  end

  def act_rules_description
    self.class.act_rules_description(distribution_config)
  end

  # Human-readable summary of rules
  def rules_summary
    parts = []

    # Allocation summary
    allocation_steps.each do |step|
      case step["type"]
      when "flat"
        parts << "House gets $#{step['amount']} flat"
      when "percentage"
        if step["person_id"].present?
          # Individual allocation to a specific person
          person = Person.find_by(id: step["person_id"])
          name = person&.name || "Person ##{step['person_id']}"
          label = step["label"].presence || name
          parts << "#{label} gets #{step['value']}%"
        else
          parts << "House gets #{step['value']}%"
        end
      when "expenses_first"
        parts << "Expenses covered first"
      when "remainder"
        # implicit
      end
    end

    # Distribution summary
    case distribution_method
    when "equal"
      parts << "Split equally among performers"
    when "shares"
      parts << "Split by shares"
    when "per_ticket"
      parts << "$#{distribution_config['per_ticket_rate']}/ticket per performer"
    when "per_ticket_guaranteed"
      parts << "$#{distribution_config['per_ticket_rate']}/ticket (min $#{distribution_config['minimum']})"
    when "flat_fee"
      parts << "$#{distribution_config['flat_amount']} flat per performer"
    when "per_act"
      parts << "Paid by acts (#{act_rules_description})"
    when "no_pay"
      parts << "Performers aren't paid"
    end

    parts.join(" → ")
  end
end
