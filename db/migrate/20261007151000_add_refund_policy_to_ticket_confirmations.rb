# frozen_string_literal: true

# Buyers' confirmation emails say the refund policy they bought under
# (Round 10). Re-seeds the two templates with the {{refund_policy}} line.
class AddRefundPolicyToTicketConfirmations < ActiveRecord::Migration[8.1]
  def up
    TicketingTemplates.ensure!(keys: %w[ticket_order_confirmation ticket_purchase_confirmation], overwrite: true)
  end

  def down; end
end
