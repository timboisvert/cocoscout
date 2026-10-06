# frozen_string_literal: true

# Works out tax on one taxed unit (a ticket, later a course registration) from
# the theater's rules. The single engine for every kind of money we collect.
#
# The rule that applies is the most specific one for that money kind: a
# ticket tier's, then its listing's, its production's, its venue's, then the
# org's default. A rule names rates (they add up) or marks the sale exempt.
#
#   added    — tax on top of the price: $20 at 10.25% → $2.05 more.
#   included — tax inside the price: $20 at 10.25% holds $1.86 of tax.
#
# Rounding is half up, per unit, per rate, so a refund of one ticket returns
# exactly the tax that ticket carried.
class TaxCalculator
  Line = Data.define(:tax_rate, :name, :rate_bps, :jurisdiction, :remitter,
                     :included, :exempt, :exemption_reason, :base_cents, :tax_cents)

  Result = Data.define(:mode, :lines) do
    def tax_cents
      lines.sum(&:tax_cents)
    end

    # Tax to add to what the buyer pays (nothing when it's inside the price).
    def added_cents
      mode == "added" ? tax_cents : 0
    end
  end

  NONE = Result.new(mode: "added", lines: []).freeze

  def self.rule_for(organization, money_kind, scopes: [])
    rules = organization.tax_rules.where(money_kind: money_kind)
    scopes.compact.each do |scope|
      rule = rules.find_by(scope_type: scope.class.polymorphic_name, scope_id: scope.id)
      return rule if rule
    end
    rules.find_by(scope_type: nil)
  end

  def self.for_ticket(listing, tier, base_cents)
    rule = rule_for(listing.organization, "tickets",
                    scopes: [ tier, listing, listing.production, listing.show.location ])
    quote(rule, base_cents)
  end

  # A credit pass (punch card, season pass) is admission paid in advance, so
  # it's taxed at purchase as tickets are: the rule of the productions it
  # covers, else the org's ticket default.
  def self.for_pass(pass, base_cents)
    rule = rule_for(pass.organization, "tickets", scopes: pass.coverages.map(&:production))
    quote(rule, base_cents)
  end

  # A course registration: the course's own rule, its production's, or the
  # org's default for courses.
  def self.for_course(offering, base_cents)
    rule = rule_for(offering.production.organization, "courses", scopes: [ offering, offering.production ])
    quote(rule, base_cents)
  end

  # A product sold with the tickets is taxed as the tickets are (the one
  # ticket tax setting), unless the product is marked not taxable.
  def self.for_product(listing, offer, base_cents)
    return NONE unless offer.taxable

    rule = rule_for(listing.organization, "tickets", scopes: [ listing, listing.production, listing.show.location ])
    quote(rule, base_cents)
  end

  def self.quote(rule, base_cents)
    return NONE if rule.nil?

    if rule.exempt?
      return Result.new(mode: rule.mode, lines: [
        Line.new(tax_rate: nil, name: "Exempt", rate_bps: 0, jurisdiction: nil, remitter: "organization",
                 included: rule.included?, exempt: true, exemption_reason: rule.exemption_reason,
                 base_cents: base_cents, tax_cents: 0)
      ])
    end

    rates = rule.tax_rates.current.order(:id).to_a
    return NONE if rates.empty?

    rule.included? ? included_lines(rule, rates, base_cents) : added_lines(rule, rates, base_cents)
  end

  def self.added_lines(rule, rates, base_cents)
    Result.new(mode: "added", lines: rates.map { |rate|
      line(rate, included: false, base_cents: base_cents, tax_cents: round_half_up(base_cents * rate.rate_bps, 10_000))
    })
  end

  # A price that already holds tax: pull the tax out of the whole price, then
  # share it between the rates by size (the last rate takes the leftover cent).
  def self.included_lines(rule, rates, price_cents)
    total_bps = rates.sum(&:rate_bps)
    net = round_half_up(price_cents * 10_000, 10_000 + total_bps)
    total_tax = price_cents - net
    remaining = total_tax
    lines = rates.each_with_index.map do |rate, i|
      share = i == rates.size - 1 ? remaining : (total_tax * rate.rate_bps) / total_bps
      remaining -= share
      line(rate, included: true, base_cents: net, tax_cents: share)
    end
    Result.new(mode: "included", lines: lines)
  end

  def self.line(rate, included:, base_cents:, tax_cents:)
    Line.new(tax_rate: rate, name: rate.label, rate_bps: rate.rate_bps, jurisdiction: rate.jurisdiction,
             remitter: rate.remitter, included: included, exempt: false, exemption_reason: nil,
             base_cents: base_cents, tax_cents: tax_cents)
  end

  def self.round_half_up(numerator, denominator)
    (numerator + (denominator / 2)) / denominator
  end

  private_class_method :added_lines, :included_lines, :line, :round_half_up
end
