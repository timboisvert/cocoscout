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

  # Before a withdrawal: how much more can go free this month, and what the
  # part over costs. Nil when withdrawals aren't billed (not Pro, usage comped).
  def withdrawal_fee_note(organization)
    return nil unless organization.bills_usage?

    free = number_to_currency(UsageRules::FREE_WITHDRAWAL_CENTS / 100.0, precision: 0)
    left = UsageMonth.new(organization).free_withdrawal_left_cents
    if left.positive?
      "Withdrawals are free up to #{free} a month: #{number_to_currency(left / 100.0)} left this month. Above that, we pass on our payment provider's 0.25% on the part over, on your monthly bill."
    else
      "You've withdrawn #{free} this month, the free amount. On anything more, we pass on our payment provider's 0.25% (#{number_to_currency(2.5)} per #{number_to_currency(1_000, precision: 0)}), on your monthly bill."
    end
  end
end
