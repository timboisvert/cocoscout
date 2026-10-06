# frozen_string_literal: true

# One email for a checkout with several shows (a pass): every show's tickets
# together (TicketingTemplates).
class AddTicketPurchaseConfirmationTemplate < ActiveRecord::Migration[8.1]
  def up
    TicketingTemplates.ensure!(keys: %w[ticket_purchase_confirmation])
  end

  def down
    ContentTemplate.where(key: "ticket_purchase_confirmation").destroy_all
  end
end
