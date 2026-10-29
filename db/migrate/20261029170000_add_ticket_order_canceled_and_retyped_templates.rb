# frozen_string_literal: true

# A comp canceled tells the guest (ticket_order_canceled), and tickets moved
# to another ticket type on the same date say so (ticket_order_retyped)
# (Tim, 2026-10-29).
class AddTicketOrderCanceledAndRetypedTemplates < ActiveRecord::Migration[8.1]
  def up
    TicketingTemplates.ensure!(keys: %w[ticket_order_canceled ticket_order_retyped])
  end

  def down; end
end
