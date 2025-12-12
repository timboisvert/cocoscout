class CreateEventLinkages < ActiveRecord::Migration[8.1]
  def change
    create_table :event_linkages do |t|
      t.string :name
      t.references :production, null: false, foreign_key: true

      t.timestamps
    end
  end
end
