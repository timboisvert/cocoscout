# frozen_string_literal: true

# A date can switch off the production's products for itself, and a
# production says whether its products are also sold at the door (off unless
# it does: a pre-sold bottle isn't a door item).
class AddProductSwitchesToTicketing < ActiveRecord::Migration[8.1]
  def change
    add_column :ticket_listings, :sell_products, :boolean, null: false, default: true
    add_column :production_ticketings, :products_at_door, :boolean, null: false, default: false
  end
end
