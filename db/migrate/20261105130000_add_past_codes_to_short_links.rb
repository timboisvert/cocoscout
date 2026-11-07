# frozen_string_literal: true

# A link's code can be swapped for a new one at any time. The codes it had
# before keep forwarding (a poster already printed still works); they're just
# never shown again.
class AddPastCodesToShortLinks < ActiveRecord::Migration[8.1]
  def change
    add_column :short_links, :past_codes, :string, array: true, default: [], null: false
    add_index :short_links, :past_codes, using: :gin
  end
end
