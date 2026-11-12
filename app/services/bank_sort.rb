# frozen_string_literal: true

# Sorting what's waiting on the bank page (Tim, 2026-11-03: "assume someone
# has a shitload to bring in"). Two parts, on one page (BankSortController):
#
# 1. The payees seen more than once (BankPayees groups with two lines or
#    more, no rule fitting them yet, not dismissed): one a screen, most
#    lines first. Record every time or ignore every time writes a rule and
#    runs it over the group's open lines; "it varies" dismisses the payee
#    for good; skip puts it off, and the skipped come back once at the end
#    of part 1. Checks have no payee for a rule to go on: they are shown
#    once and left for part 2.
# 2. The rest, one line a screen, newest first: record it (the categories
#    used most as quick answers), ignore it with a note, match it when the
#    matcher found something, or skip it. Any answer can become a rule for
#    the payee when the bank names one.
#
# The pass is a BankSortPass, one per person and organization: the count
# waiting when it started (for the progress band), rules made, and what
# was skipped. Stopping removes it.
module BankSort
  # From this many lines waiting, the bank page says so and offers sorting.
  THRESHOLD = 50
  QUICK = 5

  class << self
    # The payees part 1 goes through: groups seen more than once that no
    # rule fits and nobody said "it varies" to, most lines first.
    def payees(organization, waiting: organization.bank_statement_lines.to_deal_with.to_a, rules: organization.bank_rules.to_a)
      dismissed = organization.bank_rule_dismissals.pluck(:phrase, :direction).to_set
      BankPayees.groups(organization, lines: waiting).select do |group|
        group.count >= 2 && !dismissed.include?([ group.key, group.direction ]) && rules.none? { |r| group.lines.any? { |l| r.matches?(l) } }
      end
    end

    # The categories this organization records most, for the quick answers.
    # kind: "in" or "out". Choices the organization offers, most used first,
    # filled up with the first of the list.
    def quick_choices(organization, kind)
      choices = kind == "in" ? MoneyCategories.income_choices(organization) : MoneyCategories.spending_choices(organization)
      used = organization.money_records.where(kind: kind).group(:category_key).count.sort_by { |_, n| -n }.map(&:first)
      picked = used.filter_map { |key| choices.find { |c| c.key == key } }.first(QUICK)
      (picked + choices.reject { |c| picked.include?(c) || c.key == "other" }).first(QUICK)
    end

    # What a payee group is likeliest to be, when its kind gives it away:
    # [category_key, counterparty] or nil. Said as a guess on the page.
    def guess(organization, group)
      offered = (group.direction == "in" ? MoneyCategories.income_choices(organization) : MoneyCategories.spending_choices(organization)).map(&:key)
      key = case group.kind
      when "provider" then "tickets"
      when "fee" then "bank_fees"
      when "zelle_to" then "staff_pay" if group.steady?
      end
      return nil unless key && offered.include?(key)

      [ key, (BankPayees::KIND_NAMES.key?(group.kind) ? nil : group.name) ]
    end

    # A rule from a payee group (and the sibling groups taken with it).
    def rule_for(organization, groups, action:, category_key: nil, counterparty: nil, on_import: true, by: nil)
      organization.bank_rules.new(contains: groups.flat_map(&:phrases).uniq { |p| p.downcase }.join(", "), direction: groups.first.direction, action: action,
                                  category_key: (action == "record" ? category_key : nil), counterparty: (action == "record" ? counterparty.presence : nil),
                                  on_import: on_import, created_by: by)
    end
  end
end
