# frozen_string_literal: true

# Whether managers may refund tickets once a show has happened. Off by
# default: many theaters never refund after the fact, and then the option
# shouldn't even appear.
class AddRefundsAfterShowToTicketingProfiles < ActiveRecord::Migration[8.1]
  def change
    add_column :ticketing_profiles, :refunds_after_show, :boolean, null: false, default: false
  end
end
