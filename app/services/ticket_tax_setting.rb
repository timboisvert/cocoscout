# frozen_string_literal: true

# Ticketing's v1 tax setup: one name and percentage for every ticket, added on
# top or included in the price. Underneath it's an ordinary org-wide ticket
# rule and rate (see TaxCalculator), so venue rules and exemptions can come
# later without changing anything already recorded.
class TicketTaxSetting
  Form = Data.define(:name, :percent, :mode) do
    def set?
      percent.present?
    end
  end

  def self.current(organization)
    rule = default_rule(organization)
    rate = rule && rule.tax_rates.current.order(:id).first
    Form.new(name: rate&.name || "Sales tax", percent: rate&.percent_label&.delete("%"), mode: rule&.mode || "added")
  end

  # A blank or zero percent means tickets carry no tax. A rate that sales have
  # already used is never edited: it's retired and a new one starts, so past
  # sales keep the rate they were charged.
  def self.save!(organization, name:, percent:, mode:)
    bps = to_bps(percent)
    rule = default_rule(organization)

    if bps.nil? || bps.zero?
      rule&.destroy!
      return nil
    end

    name = name.to_s.squish.presence || "Sales tax"
    mode = TaxRule::MODES.include?(mode) ? mode : "added"

    TaxRule.transaction do
      rate = rule && rule.tax_rates.current.order(:id).first
      if rate && (rate.rate_bps != bps || rate.name != name)
        if rate.used?
          rate.update!(archived_at: Time.current)
          rate = nil
        else
          rate.update!(name: name, rate_bps: bps)
        end
      end
      rate ||= organization.tax_rates.create!(name: name, rate_bps: bps, kind: "sales")

      rule ||= organization.tax_rules.build(money_kind: "tickets")
      rule.update!(mode: mode, exempt: false, exemption_reason: nil, tax_rate_ids: [ rate.id ])
      rule
    end
  end

  def self.default_rule(organization)
    organization.tax_rules.find_by(money_kind: "tickets", scope_type: nil)
  end

  # "10.25", "10.25%", " 9 " → basis points. Rejects anything that isn't a
  # percentage between 0 and 100.
  def self.to_bps(percent)
    text = percent.to_s.strip.delete("%")
    return nil if text.empty?

    value = BigDecimal(text)
    raise ArgumentError, "Tax must be between 0% and 100%" unless value.between?(0, 100)

    (value * 100).round.to_i
  rescue ArgumentError, TypeError => e
    raise ArgumentError, e.message.start_with?("Tax must") ? e.message : "Enter the tax as a percentage, like 10.25"
  end

  private_class_method :default_rule, :to_bps
end
