# frozen_string_literal: true

# A buyer disputed their card charge with their bank. Stripe takes the
# disputed amount back, plus its $15 fee, out of CocoScout's balance — so it
# comes out of the theater's money, in the cash ledger and the books. Winning
# the dispute brings both back. Evidence is submitted from Stripe's dashboard
# for now (check-in time and the buyer's details are on the order).
class TicketDispute
  STRIPE_FEE_CENTS = 1_500

  def self.handle(dispute, event_type)
    order = TicketOrder.find_by(stripe_payment_intent_id: dispute.payment_intent) if dispute.payment_intent.present?
    order ||= TicketOrder.find_by(stripe_charge_id: dispute.charge) if dispute.charge.present?
    return unless order

    case event_type
    when "charge.dispute.created" then opened!(order, dispute.amount.to_i)
    when "charge.dispute.closed" then closed!(order) if dispute.status == "won"
    end
  end

  def self.opened!(order, amount_cents)
    cents = amount_cents + STRIPE_FEE_CENTS
    listing = order.ticket_listing
    OrgCashEntry.post!(organization: order.organization, entry_type: "ticket_dispute", amount_cents: -cents,
                       source: order, description: "Disputed ticket charge #{order.code}")
    TicketingNotifier.notify(order.organization, :dispute, variables: TicketingNotificationContent.dispute(order, opened: true, amount_cents: amount_cents),
                                                         about: order, occasion: "opened", once: true)
    LedgerPosting.post!(organization: order.organization, source: order, kind: "dispute",
                        entry_date: Date.current, cash_date: Date.current, memo: "Disputed ticket charge #{order.code}",
                        lines: [
                          { account: :cocoscout_balance, amount_cents: -cents },
                          { account: :other_expenses, amount_cents: cents, show: listing.show, production: listing.production }
                        ])
  end

  def self.closed!(order)
    entry = OrgCashEntry.find_by(source_type: "TicketOrder", source_id: order.id, entry_type: "ticket_dispute")
    OrgCashEntry.unpost!(source: order, entry_type: "ticket_dispute")
    LedgerPosting.unpost!(source: order, kind: "dispute")
    return unless entry

    TicketingNotifier.notify(order.organization, :dispute, variables: TicketingNotificationContent.dispute(order, opened: false, amount_cents: -entry.amount_cents - STRIPE_FEE_CENTS),
                                                         about: order, occasion: "won", once: true)
  end

  def self.open?(order)
    OrgCashEntry.exists?(source_type: "TicketOrder", source_id: order.id, entry_type: "ticket_dispute")
  end
end
