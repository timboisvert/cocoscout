# frozen_string_literal: true

# Runs an organization's bank rules over the lines waiting on the bank page
# (Books V1.3, plan D3). The first rule that fits a line wins: a record
# rule writes a MoneyRecord (the bank's description as the note, the line's
# date and amount, from the bank) and the line is recorded; an ignore rule
# ignores it. Small runs happen in the request; a big one goes to
# BankRulesApplyJob, which tells the person when it's done.
class BankRules
  IN_REQUEST = 30

  Result = Struct.new(:recorded, :ignored, keyword_init: true) do
    def dealt_with = recorded + ignored
  end

  # rules: the rules to run (default all of the organization's).
  # lines: the lines to run them over (default every line waiting).
  def self.apply!(organization, rules: organization.bank_rules.order(:id).to_a, lines: organization.bank_statement_lines.to_deal_with.to_a, by: nil)
    result = Result.new(recorded: 0, ignored: 0)
    rules = rules.to_a
    return result if rules.empty?

    counts = Hash.new(0)
    lines.each do |line|
      rule = rules.find { |r| r.matches?(line) }
      next unless rule

      if rule.ignore?
        line.ignore!
        result.ignored += 1
      else
        record = organization.money_records.create!(
          kind: (line.deposit? ? "in" : "out"), on: line.on, amount_cents: line.amount_cents.abs, category_key: rule.category_key,
          counterparty: rule.counterparty.presence, production: rule.production, via: "bank", memo: line.description, recorded_by: by
        )
        line.recorded!(record)
        result.recorded += 1
      end
      counts[rule.id] += 1
    end
    counts.each { |id, n| BankRule.where(id: id).update_all([ "applied_count = applied_count + ?", n ]) }
    result
  end

  # How many lines waiting a rule would fit, and a few of them, for the
  # rule form as it is typed.
  def self.preview(organization, contains:, direction:)
    rule = BankRule.new(organization: organization, contains: contains, direction: direction.presence_in(BankRule::DIRECTIONS) || "any")
    return { count: 0, samples: [] } if rule.phrases.empty?

    lines = rule.waiting_lines
    { count: lines.size, samples: lines.map(&:description).uniq.first(4) }
  end

  # The "applying" flag the bank page shows while a run is in the background.
  def self.applying_key(organization) = "bank_rules_applying:#{organization.id}"
  def self.applying?(organization) = Rails.cache.read(applying_key(organization)).present?
end
