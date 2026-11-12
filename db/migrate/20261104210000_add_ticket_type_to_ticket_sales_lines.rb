# frozen_string_literal: true

# Tickets sold on another site name their ticket type everywhere (Tim,
# 2026-11-04). A show sold through CocoScout already keeps that by type
# (ticket_outside_sales); a show CocoScout doesn't sell keeps it here, on
# the line typed for it. Blank on older lines, which read as the plain
# ticket (SettleUp::PLAIN_TICKET).
class AddTicketTypeToTicketSalesLines < ActiveRecord::Migration[8.1]
  def change
    add_column :ticket_sales_lines, :ticket_type, :string
  end
end
