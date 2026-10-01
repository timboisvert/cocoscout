# frozen_string_literal: true

# Comps given from the show page: who gave them, and a note for the
# theater's records ("Guest of the cast").
class AddCompFieldsToTicketOrders < ActiveRecord::Migration[8.1]
  def change
    add_reference :ticket_orders, :issued_by, foreign_key: { to_table: :users, on_delete: :nullify }
    add_column :ticket_orders, :note, :string
  end
end
