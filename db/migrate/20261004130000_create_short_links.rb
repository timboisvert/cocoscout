# frozen_string_literal: true

# cocoscout.com/t/CODE: one short code per production's ticketing (and one for
# the box office), issued once and kept forever, plus named links a manager
# makes to see which poster or post sells. Orders remember the link that
# brought the buyer.
class CreateShortLinks < ActiveRecord::Migration[8.1]
  def up
    create_table :short_links do |t|
      t.references :organization, null: true, foreign_key: true
      t.string :code, null: false
      t.string :target_type
      t.bigint :target_id
      t.jsonb :query, null: false, default: {}
      t.string :kind, null: false, default: "canonical"
      t.string :label
      t.integer :clicks_count, null: false, default: 0
      t.datetime :last_clicked_at
      t.references :created_by, null: true, foreign_key: { to_table: :users }
      t.datetime :archived_at
      t.timestamps
    end
    add_index :short_links, :code, unique: true
    add_index :short_links, [ :target_type, :target_id ]
    add_index :short_links, [ :target_type, :target_id ], unique: true, where: "kind = 'canonical'",
              name: "index_short_links_canonical_per_target"
    add_reference :ticket_orders, :short_link, null: true, foreign_key: true

    # Codes for what's already set up (dev and sandbox; prod has no ticketing yet).
    say_with_time "issuing codes to existing productions with ticketing and to box offices" do
      ShortLink.reset_column_information
      ProductionTicketing.includes(:production).find_each { |setup| ShortLink.canonical_for!(setup.production) }
      TicketingProfile.find_each { |profile| ShortLink.canonical_for!(profile) }
    end
  end

  def down
    remove_reference :ticket_orders, :short_link
    drop_table :short_links
  end
end
