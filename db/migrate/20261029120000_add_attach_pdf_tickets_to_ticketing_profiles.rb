# frozen_string_literal: true

# PDF tickets (advanced ticketing §7a): an organization can attach the
# buyer's tickets as a PDF to the confirmation email. Off until they turn it
# on in Ticketing → Settings → Box office (Tim, 2026-10-29); the order page's
# download works either way. The confirmation emails gain a line saying the
# PDF is attached, shown only when it is.
class AddAttachPdfTicketsToTicketingProfiles < ActiveRecord::Migration[8.1]
  def up
    add_column :ticketing_profiles, :attach_pdf_tickets, :boolean, default: false, null: false
    TicketingTemplates.ensure!(keys: %w[ticket_order_confirmation ticket_purchase_confirmation], overwrite: true)
  end

  def down
    remove_column :ticketing_profiles, :attach_pdf_tickets
  end
end
