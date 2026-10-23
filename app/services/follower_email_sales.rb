# frozen_string_literal: true

# Tickets and money each email to followers brought in: paid orders whose
# checkout started from one of its links (utm "campaign" => "fe-<id>").
class FollowerEmailSales
  # { follower_email_id => { tickets:, cents: } }
  def self.for(organization, emails)
    keys = Array(emails).to_h { |email| [ email.campaign_key, email.id ] }
    return {} if keys.empty?

    campaign = Arel.sql("ticket_orders.utm ->> 'campaign'")
    orders = organization.ticket_orders.where(status: "paid").where("ticket_orders.utm ->> 'campaign' IN (?)", keys.keys)
    cents = orders.group(campaign).sum(:total_cents)
    tickets = Ticket.joins(:ticket_order).merge(orders).group(campaign).count
    keys.each_with_object({}) do |(key, id), result|
      next unless cents.key?(key)

      result[id] = { tickets: tickets[key].to_i, cents: cents[key].to_i }
    end
  end

  # Per date, for a sent email's page: [{ show:, tickets:, cents: }]
  def self.by_show(follower_email)
    orders = follower_email.ticket_orders.includes(ticket_listing: { show: :production })
    tickets = Ticket.where(ticket_order_id: orders.select(:id)).group(:ticket_order_id).count
    orders.group_by { |order| order.ticket_listing&.show }.filter_map do |show, list|
      next unless show

      { show: show, tickets: list.sum { |order| tickets[order.id].to_i }, cents: list.sum(&:total_cents) }
    end.sort_by { |row| row[:show].date_and_time }
  end
end
