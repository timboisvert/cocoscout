# frozen_string_literal: true

# What settling a day puts on the books, in one entry (kind "settlement",
# plan §9.2): today, the door cash over or short (a short is a cost, an over
# is other income; the cash itself is already counted sale by sale). The
# shows' own money posts from their financials as it always has. Reopening
# withdraws the entry; settling again restates it, dated the original day.
#
# A register's day (Square, plan §9.3) posts here too, and only here: sales
# to income by category, the register's fees to card fees, sales tax to tax
# to pay, refunds against income, tips to Tips owed to staff, and the net
# to Bank (there is no bank matching yet to clear it through; a matched
# deposit later just confirms the line). Each person's tip share then waits
# on Pay People with the approved hours (Tim, 2026-11-03: nothing goes on
# the run until the week's pay is put there together), or came out of door
# cash when it was handed over at close.
class SettlementPoster
  CATEGORY_ACCOUNTS = { "bar" => :bar_income, "food" => :bar_income, "merchandise" => :merchandise_income, "other" => :other_income }.freeze

  def self.post!(record)
    organization = record.organization
    day = SettleUp.day(organization, record.date)
    lines = door_cash_lines(day) + register_lines(day) + tip_lines(day, record)
    LedgerPosting.post!(organization: organization, source: record, kind: "settlement", entry_date: record.date, cash_date: record.date,
                        memo: "Settled #{record.date.strftime('%b %-d, %Y')}", lines: lines)
  rescue StandardError => e
    raise if Rails.env.test?

    Rails.logger.error("[SettlementPoster] day #{record.id}: #{e.class}: #{e.message}")
  end

  def self.unpost!(record)
    LedgerPosting.unpost!(source: record, kind: "settlement")
    unpay_tips!(record)
  end

  def self.door_cash_lines(day)
    diff = day.door_cash.over_short_cents.to_i
    if diff.negative?
      [ { account: :other_expenses, amount_cents: -diff, memo: "Door cash short" }, { account: :door_cash, amount_cents: diff } ]
    elsif diff.positive?
      [ { account: :door_cash, amount_cents: diff }, { account: :other_income, amount_cents: -diff, memo: "Door cash over" } ]
    else
      []
    end
  end

  def self.register_lines(day)
    day.registers.flat_map do |register|
      integration = register.integration
      lines = []
      net = 0
      if integration.brings?("sales")
        sales = register.sales_by_category.transform_values(&:to_i)
        total = sales.values.sum
        refunds = integration.brings?("refunds") ? register.refunds_cents : 0
        sales.each do |category, cents|
          # Refunds come off each category in proportion.
          back = total.positive? ? (refunds * cents / total.to_f).round : 0
          lines << { account: CATEGORY_ACCOUNTS.fetch(category, :other_income), amount_cents: -(cents - back), memo: "#{register.location_name}: #{Integration::REGISTER_CATEGORIES.fetch(category, 'Other')}" }
          net += cents - back
        end
      end
      if integration.brings?("tax")
        lines << { account: :tax_to_remit, amount_cents: -register.tax_cents, memo: "#{register.location_name}: sales tax" }
        net += register.tax_cents
      end
      if integration.brings?("tips")
        lines << { account: :tips_owed, amount_cents: -register.tips_cents, memo: "#{register.location_name}: tips" }
        net += register.tips_cents
      end
      if integration.brings?("fees")
        lines << { account: :ticketing_fees, amount_cents: register.fees_cents, memo: "#{register.location_name}: card fees" }
        net -= register.fees_cents
      end
      lines << { account: :bank, amount_cents: net, memo: "#{register.location_name}: on its way to the bank" }
      lines
    end
  end

  # Tips handed over in cash at close came out of the door cash box; tips
  # nobody was given (a stretch the house keeps, by the manager's say) are
  # the house's income, not owed to anyone.
  def self.tip_lines(day, record)
    lines = []
    cash = record.cash_tips_cents
    lines.concat([ { account: :tips_owed, amount_cents: cash, memo: "Tips paid in cash at close" }, { account: :door_cash, amount_cents: -cash } ]) if cash.positive?
    house = day.tips.cents - record.tip_shares.sum(&:amount_cents)
    lines.concat([ { account: :tips_owed, amount_cents: house, memo: "Tips kept by the house" }, { account: :other_income, amount_cents: -house, memo: "Tips kept by the house" } ]) if house.positive?
    lines
  end

  # Reopening takes back a share that Pay People already put on a run, while
  # that run is still a draft; once a run is funded the money has moved and
  # the share stands. Shares still waiting on Pay People just stop waiting.
  def self.unpay_tips!(record)
    record.tip_shares.where.not(payout_contribution_id: nil).includes(payout_contribution: %i[payout_batch payout_batch_item]).each do |share|
      contribution = share.payout_contribution
      next unless contribution&.payout_batch&.open?

      item = contribution.payout_batch_item
      batch = contribution.payout_batch
      share.update!(payout_contribution: nil)
      contribution.destroy!
      item.reload
      if item.payout_contributions.none?
        item.destroy!
      else
        item.settle_amount!
      end
      batch.recalculate_total!
    end
  end
end
