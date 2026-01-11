# frozen_string_literal: true

class PayoutScheme < ApplicationRecord
  # Distribution methods
  DISTRIBUTION_METHODS = %w[equal shares per_ticket per_ticket_guaranteed flat_fee].freeze

  belongs_to :production

  has_many :show_payouts, dependent: :nullify

  validates :name, presence: true
  validates :name, uniqueness: { scope: :production_id }
  validates :rules, presence: true

  scope :default_first, -> { order(is_default: :desc, created_at: :asc) }

  # Preset templates for quick setup
  PRESETS = {
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
          { type: "expenses_first" },
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
          { type: "expenses_first" },
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

  def self.create_from_preset(production, preset_key)
    preset = PRESETS[preset_key.to_sym]
    return nil unless preset

    production.payout_schemes.create(
      name: preset[:name],
      description: preset[:description],
      rules: preset[:rules]
    )
  end

  def self.preset_options
    PRESETS.map { |key, preset| [ preset[:name], key ] }
  end

  # Mark this scheme as the default (unmark others)
  def make_default!
    transaction do
      production.payout_schemes.where.not(id: id).update_all(is_default: false)
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
        parts << "House gets #{step['value']}%"
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
