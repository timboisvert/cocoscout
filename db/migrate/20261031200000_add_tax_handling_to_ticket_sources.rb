# frozen_string_literal: true

# Who pays the tax on tickets another site sold (Books V1.3, Tim 10/31):
# the site collects it and pays it for the organization (Eventbrite in
# Chicago), the organization owes it (Ticket Tailor), or there is none.
class AddTaxHandlingToTicketSources < ActiveRecord::Migration[8.1]
  def change
    add_column :ticket_sources, :tax_handling, :string, null: false, default: "none"
  end
end
