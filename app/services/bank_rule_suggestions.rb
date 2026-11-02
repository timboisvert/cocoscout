# frozen_string_literal: true

# Rules the bank page suggests (Books V1.3, plan D3; Tim, 2026-11-02),
# from this organization's own statement lines and what was done with
# them, never another organization's. Lines are grouped by the payee the
# bank's description names (the first words of the description key, after
# the words that name nobody); a payee seen more than once, with no rule
# that already fits it and not dismissed, becomes a suggestion:
#
# - recorded by hand before: record as the category and payee used most
#   (a yes makes the rule and runs it);
# - ignored by hand before, never recorded: ignore (same);
# - only waiting: a rule with the phrase and direction filled in, for the
#   person to finish with a category.
#
# Each suggestion says how many lines waiting it would catch and how many
# times the payee has been seen in all.
class BankRuleSuggestions
  # Words that name nobody, so they never start a phrase.
  STOP = %w[ZELLE TO FROM INC LLC CO CORP THE AND OF DES PMT PAY PAYMENTS CHECK CHK CARD VISA MC ONLINE MOBILE
            RECURRING AUTOPAY BILL BILLPAY EPAY WEB TEL ACH ATM CASH FEE FEES TRANSACTION TRANSFER SAVINGS CHECKING].to_set.freeze
  LIMIT = 20

  Suggestion = Struct.new(:phrase, :direction, :action, :category_key, :counterparty, :category_label, :waiting_count, :seen_count, :times, :samples, keyword_init: true) do
    def record? = action == "record"
    def ignore? = action == "ignore"
    def ready? = action.present?
    def key = Digest::SHA1.hexdigest("#{phrase}|#{direction}")[0, 12]
  end

  def self.for(organization)
    new(organization).suggestions
  end

  def initialize(organization)
    @organization = organization
  end

  def suggestions
    lines = @organization.bank_statement_lines.select(:id, :description, :description_key, :amount_cents, :state, :money_record_id).to_a
    return [] if lines.empty?

    rules = @organization.bank_rules.to_a
    dismissed = @organization.bank_rule_dismissals.pluck(:phrase, :direction).to_set
    records = MoneyRecord.where(id: lines.filter_map(&:money_record_id)).pluck(:id, :category_key, :counterparty).to_h { |id, c, p| [ id, [ c, p ] ] }

    groups = lines.group_by { |l| [ self.class.phrase_for(l), l.deposit? ? "in" : "out" ] }
    groups.filter_map do |(phrase, direction), group|
      next if phrase.blank? || group.size < 2 || dismissed.include?([ phrase, direction ])

      rule = BankRule.new(organization: @organization, contains: phrase, direction: direction)
      next if group.none? { |l| rule.matches?(l) }
      next if rules.any? { |r| group.any? { |l| r.matches?(l) } }

      suggestion_for(phrase, direction, group, records)
    end.sort_by { |s| [ -s.waiting_count, -s.seen_count ] }.first(LIMIT)
  end

  # The payee the bank's description names: the first two words of the
  # description key that name someone (one, when that's all there is).
  def self.phrase_for(line)
    words = line.description_key.to_s.split.reject { |w| STOP.include?(w) || w.size < 2 }
    words.first(2).join(" ").presence
  end

  private

  def suggestion_for(phrase, direction, group, records)
    done = group.filter_map { |l| records[l.money_record_id] if l.state == "recorded" }
    ignored = group.count { |l| l.state == "ignored" }
    waiting = group.count { |l| l.state.in?(%w[open suggested]) }
    action, category_key, counterparty, times = if done.any?
      (category, payee), n = done.tally.max_by { |_, c| c }
      [ "record", category, payee, n ]
    elsif ignored.positive?
      [ "ignore", nil, nil, ignored ]
    end
    label = category_key && MoneyCategories.label_for(category_key, direction == "in" ? :income : :spending, organization: @organization)
    Suggestion.new(phrase: phrase, direction: direction, action: action, category_key: category_key, counterparty: counterparty, category_label: label,
                   waiting_count: waiting, seen_count: group.size, times: times, samples: group.map(&:description).uniq.first(3))
  end
end
