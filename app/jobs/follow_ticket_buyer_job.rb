# frozen_string_literal: true

# After a paid order (or pass purchase): records what they bought on the
# organization's follower (FollowerSource, what segments read), and adds them
# to each list they ticked at checkout. Someone who unsubscribed, bounced or
# complained is never put back. A buyer who ticked nothing still has their
# purchase recorded, but joins no list, so nothing is ever sent to them.
class FollowTicketBuyerJob < ApplicationJob
  queue_as :default

  def perform(order_id = nil, purchase_id: nil)
    if order_id
      order = TicketOrder.includes(ticket_listing: :show).find_by(id: order_id)
      return unless order && order.status == "paid" && order.buyer_email.present?

      follow!(order.organization, order.buyer_email, order.buyer_name, order.follow_list_ids,
              production_id: order.ticket_listing&.production_id, show_id: order.ticket_listing&.show_id,
              ticket_order_id: order.id, at: order.paid_at)
    elsif purchase_id
      purchase = TicketPurchase.find_by(id: purchase_id)
      holding = purchase&.ticket_pass_holdings&.first
      return unless holding && holding.holder_email.present?

      follow!(purchase.organization, holding.holder_email, holding.holder_name, purchase.follow_list_ids, at: purchase.paid_at)
    end
  end

  private

  def follow!(organization, email, name, list_ids, production_id: nil, show_id: nil, ticket_order_id: nil, at: nil)
    return unless organization&.on_paid_plan?
    return unless email.to_s.match?(URI::MailTo::EMAIL_REGEXP)

    follower = Follower.for!(organization, email, name: name, consented: Array(list_ids).any?)
    if ticket_order_id.nil? || !follower.follower_sources.exists?(ticket_order_id: ticket_order_id)
      follower.follower_sources.create!(kind: "checkout", production_id: production_id, show_id: show_id,
                                        ticket_order_id: ticket_order_id, occurred_at: at || Time.current)
    end
    return unless follower.subscribed?

    lists = organization.mailing_lists.active.where(id: Array(list_ids))
    lists.each { |list| list.mailing_list_memberships.find_or_create_by!(follower: follower) }
  rescue ActiveRecord::RecordNotUnique
    nil
  end
end
