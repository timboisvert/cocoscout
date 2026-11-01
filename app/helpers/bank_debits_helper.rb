# frozen_string_literal: true

module BankDebitsHelper
  # Before a bank debit (funding a payout run, adding funds): whether this one
  # is free, or what it adds to the month's bill. Nil when debits aren't
  # billed (not Pro, usage comped, or funding by card).
  def bank_debit_note(organization)
    return nil unless organization.bills_usage? && organization.funding_payment_method_type != "card"

    left = UsageMonth.new(organization).free_debits_left
    fee = number_to_currency(UsageRules::EXTRA_BANK_DEBIT_CENTS / 100.0, precision: 0)
    if left.positive?
      "This bank debit is free: #{left == 1 ? 'your last' : "one of your #{left}"} free this month. After that, each is #{fee} on your monthly bill."
    else
      "You've used this month's #{UsageRules::FREE_BANK_DEBITS} free bank debits, so this one adds #{fee} to your monthly bill. Bigger, fewer debits stay free."
    end
  end
end
