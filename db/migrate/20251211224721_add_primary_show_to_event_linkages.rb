class AddPrimaryShowToEventLinkages < ActiveRecord::Migration[8.1]
  def change
    add_reference :event_linkages, :primary_show, null: true, foreign_key: { to_table: :shows }
  end
end
