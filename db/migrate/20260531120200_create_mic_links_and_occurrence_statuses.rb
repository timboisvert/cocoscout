# frozen_string_literal: true

# Two new tables:
#  * mic_links — multiple URLs per mic (signup, Instagram, website, etc.)
#  * mic_occurrence_statuses — one-off date status for self-described mics.
#    For production-linked mics we already use Show.mic_status; this is the
#    parallel surface so the public detail page renders the same chips for
#    both cases.
class CreateMicLinksAndOccurrenceStatuses < ActiveRecord::Migration[8.1]
  def change
    create_table :mic_links do |t|
      t.references :mic, null: false, foreign_key: true
      # signup | website | instagram | facebook | tiktok | x_twitter | youtube | other
      t.integer :link_type, null: false, default: 0
      t.string :url, null: false
      t.string :label
      t.integer :sort_order, null: false, default: 0
      t.timestamps
    end
    add_index :mic_links, %i[mic_id link_type]

    create_table :mic_occurrence_statuses do |t|
      t.references :mic, null: false, foreign_key: true
      t.date :occurs_on, null: false
      # scheduled | running_as_planned | cancelled | online_only | extra_spots
      t.integer :status, null: false, default: 0
      t.text :note
      t.bigint :created_by_user_id
      t.timestamps
    end
    add_index :mic_occurrence_statuses, %i[mic_id occurs_on], unique: true
  end
end
