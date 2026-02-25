# frozen_string_literal: true

class PayoutScheme < ApplicationRecord
  # Distribution methods
  DISTRIBUTION_METHODS = %w[equal shares per_ticket per_ticket_guaranteed flat_fee no_pay].freeze

  belongs_to :organization, optional: true
  belongs_to :production, optional: true

  has_many :show_payouts, dependent: :nullify
  has_many :payout_scheme_defaults, dependent: :destroy
  has_many :default_for_productions, through: :payout_scheme_defaults, source: :production

  validates :name, presence: true
  validates :rules, presence: true
  validate :must_have_organization_or_production
  validates :name, uniqueness: { scope: :organization_id }, if: -> { organization_id.present? && production_id.blank? }
  validates :name, uniqueness: { scope: :production_id }, if: -> { production_id.present? }

  scope :default_first, -> { order(is_default: :desc, created_at: :asc) }
  scope :organization_level, -> { where(production_id: nil) }
  scope :production_level, -> { where.not(production_id: nil) }
  scope :for_organization, ->(org) { where(organization: org) }
  scope :defaults, -> { where(is_default: true) }
  scope :effective_on, ->(date) { where("effective_from IS NULL OR effective_from <= ?", date) }
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

  # Find the default scheme for a given show using the payout_scheme_defaults join table
  # Priority:
  # 1. Production-specific default with effective_from <= show date (most recent effective_from)
  # 2. Organization-level default (production_id nil) with effective_from <= show date
  def self.default_for_show(show)
    show_date = show.date_and_time&.to_date || Date.current
    production = show.production
    organization = production.organization

    # Try production-specific defaults first (via join table)
    production_default = PayoutSchemeDefault
      .for_production(production)
      .effective_on(show_date)
      .by_effective_date_desc
      .first
      &.payout_scheme

    return production_default if production_default

    # Fall back to organization-level defaults (production_id nil in join table)
    org_default = PayoutSchemeDefault
      .org_level
      .joins(:payout_scheme)
      .where(payout_schemes: { organization_id: organization.id })
      .effective_on(show_date)
      .by_effective_date_desc
      .first
      &.payout_scheme

    return org_default if org_default

    # Legacy fallback: check is_default flag on schemes (for migration period)
    legacy_production_default = production.payout_schemes
      .defaults
      .effective_on(show_date)
      .order(Arel.sql("CASE WHEN effective_from IS NULL THEN 0 ELSE 1 END DESC, effective_from DESC"))
      .first

    return legacy_production_default if legacy_production_default

    organization.payout_schemes
      .organization_level
      .defaults
      .effective_on(show_date)
      .order(Arel.sql("CASE WHEN effective_from IS NULL THEN 0 ELSE 1 END DESC, effective_from DESC"))
      .first
  end

  # Check if this is an organization-level scheme (not tied to a specific production)
  def organization_level?
    production_id.blank?
  end

  # Check if this is a production-specific scheme
  def production_level?
    production_id.present?
  end

  private

  def must_have_organization_or_production
    if organization_id.blank? && production_id.blank?
      errors.add(:base, "must belong to either an organization or a production")
    end
  end

  public

  # Preset templates for quick setup
  PRESETS = {
    no_pay: {
      name: "No Pay",
      description: "Non-revenue events with no performer payouts (rehearsals, workshops, etc.)",
      rules: {
        allocation: [],
        distribution: { method: "no_pay" },
        performer_overrides: {}
      }
    },
    even_split: {
      name: "Even Split (50/50)",
      description: "Split revenue evenly between house and performers, then divide equally among performers.",
      rules: {
        allocation: [
          { type: "percentage", value: 50, to: "house" },
          { type: "remainder", to: "performers" }
        ],
        distribution: { method: "equal" },
        performer_overrides: {}
      }
    },
    per_ticket: {
      name: "Per-Ticket Rate",
      description: "Pay each performer a fixed amount per ticket sold.",
      rules: {
        allocation: [
          { type: "remainder", to: "available" }
        ],
        distribution: { method: "per_ticket", per_ticket_rate: 1.0 },
        performer_overrides: {}
      }
    },
    per_ticket_guaranteed: {
      name: "Per-Ticket with Minimum",
      description: "Pay per ticket with a guaranteed minimum payout per performer.",
      rules: {
        allocation: [
          { type: "remainder", to: "available" }
        ],
        distribution: { method: "per_ticket_guaranteed", per_ticket_rate: 1.0, minimum: 25.0 },
        performer_overrides: {}
      }
    },
    flat_fee: {
      name: "Flat Fee",
      description: "Pay each performer a fixed amount regardless of ticket sales.",
      rules: {
        allocation: [],
        distribution: { method: "flat_fee", flat_amount: 50.0 },
        performer_overrides: {}
      }
    },
    share_based: {
      name: "Share-Based Split",
      description: "Divide performer pool by configurable shares per person.",
      rules: {
        allocation: [
          { type: "percentage", value: 40, to: "house" },
          { type: "remainder", to: "performers" }
        ],
        distribution: { method: "shares", default_shares: 1.0 },
        performer_overrides: {}
      }
    }
  }.freeze

  # Create a scheme from preset for a production (legacy) or organization
  def self.create_from_preset(owner, preset_key)
    preset = PRESETS[preset_key.to_sym]
    return nil unless preset

    if owner.is_a?(Organization)
      PayoutScheme.create(
        organization: owner,
        name: preset[:name],
        description: preset[:description],
        rules: preset[:rules]
      )
    else
      # Legacy production-level support
      PayoutScheme.create(
        production: owner,
        organization: owner.organization,
        name: preset[:name],
        description: preset[:description],
        rules: preset[:rules]
      )
    end
  end

  def self.preset_options
    PRESETS.map { |key, preset| [ preset[:name], key ] }
  end

  # Make this scheme the default for specific productions
  # @param production_ids [Array<Integer>] - production IDs to set as default for (empty = org-level fallback)
  # @param effective_from [Date, nil] - optional date when this default takes effect
  def set_as_default_for!(production_ids: [], effective_from: nil)
    transaction do
      # Remove existing defaults for this scheme
      payout_scheme_defaults.destroy_all

      if production_ids.empty?
        # Org-level fallback - clear conflicting org-level defaults
        PayoutSchemeDefault
          .org_level
          .joins(:payout_scheme)
          .where(payout_schemes: { organization_id: organization_id })
          .where(effective_from: effective_from)
          .destroy_all

        # Create org-level default
        payout_scheme_defaults.create!(production_id: nil, effective_from: effective_from)
      else
        # Production-specific defaults
        production_ids.each do |prod_id|
          # Clear conflicting defaults for this production/date combo
          PayoutSchemeDefault
            .where(production_id: prod_id, effective_from: effective_from)
            .destroy_all

          # Create the new default
          payout_scheme_defaults.create!(production_id: prod_id, effective_from: effective_from)
        end
      end
    end
  end

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

  # Remove a production from this scheme's defaults
  def remove_default_for_production!(production)
    payout_scheme_defaults.where(production_id: production.id).destroy_all
  end

  # Check if this scheme is default for a given production (at any date)
  def default_for_production?(production)
    payout_scheme_defaults.where(production_id: production.id).exists?
  end

  # Check if this is the org-level fallback default
  def org_level_default?
    payout_scheme_defaults.org_level.exists?
  end

  # Legacy compatibility: mark this scheme as the default (uses old is_default flag)
  # Deprecated: Use set_as_default_for! instead
  def make_default!
    transaction do
      scope = if organization_level?
                PayoutScheme.where(organization_id: organization_id, production_id: nil)
      else
                PayoutScheme.where(production_id: production_id)
      end

      # Only unmark conflicting defaults (same effective_from)
      conflicting = scope.where.not(id: id).where(is_default: true)
      if effective_from.present?
        conflicting = conflicting.where(effective_from: effective_from)
      else
        conflicting = conflicting.where(effective_from: nil)
      end

      conflicting.update_all(is_default: false)
      update!(is_default: true)
    end
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
    end

    parts.join(" → ")
  end
end
