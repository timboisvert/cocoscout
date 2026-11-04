# frozen_string_literal: true

# An organization's bank rules as a file, and back (Tim, 2026-11-03: make
# them in development, carry them to production). The file is JSON: each
# rule's phrases, direction, action, category, payee, production (by
# name) and whether it runs on statements brought in later. Importing
# skips a rule the organization already has (the same phrases, the same
# direction) and a rule whose category isn't one it offers.
class BankRulesFile
  VERSION = 1

  Result = Struct.new(:added, :already, :skipped, keyword_init: true)

  def self.export(organization)
    rules = organization.bank_rules.includes(:production).order(:id).map do |rule|
      { contains: rule.contains, direction: rule.direction, action: rule.action, category_key: rule.category_key, counterparty: rule.counterparty,
        production: rule.production&.name, on_import: rule.on_import }
    end
    JSON.pretty_generate(cocoscout_bank_rules: VERSION, organization: organization.name, exported_at: Time.current.iso8601, rules: rules)
  end

  def self.filename(organization)
    "cocoscout-bank-rules-#{organization.name.parameterize}-#{Date.current.iso8601}.json"
  end

  # Raises JSON::ParserError or ArgumentError when the file isn't ours.
  def self.import!(organization, text, by: nil)
    data = JSON.parse(text)
    raise ArgumentError, "not a rules file" unless data.is_a?(Hash) && data["cocoscout_bank_rules"] && data["rules"].is_a?(Array)

    have = organization.bank_rules.map { |r| [ r.contains.downcase, r.direction ] }.to_set
    offered = { "in" => MoneyCategories.income_choices(organization).map(&:key), "out" => MoneyCategories.spending_choices(organization).map(&:key) }
    productions = organization.productions.to_h { |p| [ p.name.downcase, p ] }
    result = Result.new(added: 0, already: 0, skipped: 0)
    data["rules"].each do |row|
      next unless row.is_a?(Hash)

      rule = organization.bank_rules.new(contains: row["contains"].to_s, direction: row["direction"].to_s, action: row["action"].to_s, category_key: row["category_key"].presence,
                                         counterparty: row["counterparty"].presence, on_import: row.fetch("on_import", true) ? true : false, created_by: by,
                                         production: (row["production"].present? ? productions[row["production"].to_s.downcase] : nil))
      rule.valid?
      if have.include?([ rule.contains.downcase, rule.direction ])
        result.already += 1
      elsif rule.errors.any? || (rule.record? && !offered.fetch(rule.direction, []).include?(rule.category_key))
        result.skipped += 1
      else
        rule.save!
        have << [ rule.contains.downcase, rule.direction ]
        result.added += 1
      end
    end
    result
  end
end
