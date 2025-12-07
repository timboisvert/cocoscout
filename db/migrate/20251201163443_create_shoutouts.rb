# frozen_string_literal: true

class CreateShoutouts < ActiveRecord::Migration[8.1]
  def change
    create_table :shoutouts do |t|
      # Polymorphic association for the recipient (person, group, etc.)
      t.references :shoutee, polymorphic: true, null: false

      # The person giving the shoutout
      t.references :author, null: false, foreign_key: { to_table: :people }

      # The content of the shoutout
      t.text :content, null: false

      t.timestamps
    end

    # Index for efficient querying of shoutouts for a specific entity
    add_index :shoutouts, %i[shoutee_type shoutee_id created_at], name: 'index_shoutouts_on_shoutee_and_created'
    add_index :shoutouts, %i[author_id created_at], name: 'index_shoutouts_on_author_and_created'
  end
end
