# frozen_string_literal: true

# A date can answer the Tickets question for itself (Round 9 §3): nil follows
# the production; "elsewhere" points at tickets_url; "none" means no tickets
# for this date. A date answering for itself isn't sold on CocoScout.
class AddTicketsModeToShows < ActiveRecord::Migration[8.1]
  def change
    add_column :shows, :tickets_mode, :string
  end
end
