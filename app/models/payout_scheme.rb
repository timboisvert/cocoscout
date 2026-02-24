# frozen_string_literal: true

class PayoutScheme < ApplicationRecord
  # Distribution methods
  DISTRIBUTION_METHODS = %w[equal shares per_ticket per_ticket_guaranteed flat_fee no_pay].freeze

  belongs_to :organization, optional: true
  belongs_to :production, optional: true

  has_many :show_payouts, dependent: :nullify

  validates :name, presence: true
  validates :rules, presence: true
  validate :must_have_organization_or_production
  validates :name, uniqueness: { scope: :organization_id }, if: -> { organization_id.present? && production_id.blank? }
  validates :name, uniqueness: { scope: :production_id }, if: -> { production_id.present? }

  scope :default_first, -> { order(is_default: :desc, created_at: :asc) }
  scope :organization_level, -> { where(production_id: nil) }
  scope :production_level, -> { where.not(production_id: nil) }
  scope :for_organization, ->(org) { where(organization: org) }

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
    no_pay: {
      name: "No Pay",
      description: "For shows that don't pay performers (non-revenue events, rehearsals, etc.).",
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

  # Mark this scheme as the default (unmark others in the same scope)
  def make_default!
    transaction do
      if organization_level?
        # Organization-level: unmark other org-level defaults in same org
        PayoutScheme.where(organization_id: organization_id, production_id: nil)
                    .where.not(id: id)
                    .update_all(is_default: false)
      else
        # Production-level: unmark other production defaults
        PayoutScheme.where(production_id: production_id)
                    .where.not(id: id)
                    .update_all(is_default: false)
      end
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
