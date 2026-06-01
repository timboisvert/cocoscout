# frozen_string_literal: true

# Block 1 of the Mics Finder build. Creates the public-finder data layer:
# venues (deduplicated public addresses), mics (the always-present record —
# optionally linked to a Production once a producer migrates), tags, city
# hubs (curated layer on top of any city listing page), and an audit log.
#
# Existing CocoScout models (Production / Show / SignUpForm / Location /
# User / Person / Message) are intentionally untouched here. The only
# cross-cutting change ships in a separate migration (Show.mic_status).
class CreateMicsFinderTables < ActiveRecord::Migration[8.1]
  def change
    create_table :venues do |t|
      t.string  :name,            null: false
      t.string  :address1
      t.string  :address2
      t.string  :neighborhood
      t.string  :city,            null: false
      t.string  :state,           null: false
      t.string  :postal_code
      t.string  :country,         null: false, default: "US"
      t.string  :timezone
      t.float   :lat
      t.float   :lng
      # bar | coffee_shop | comedy_club | basement | theater | online | other
      t.integer :venue_type,      null: false, default: 0
      # Default accessibility flags inherited by mics at this venue.
      t.jsonb   :accessibility,   null: false, default: {}
      t.datetime :geocoded_at
      t.string :geocode_error
      t.timestamps
    end
    add_index :venues, %i[city state]
    add_index :venues, %i[lat lng]

    create_table :mics do |t|
      t.string  :slug,            null: false
      t.string  :name,            null: false
      t.references :venue,        null: false, foreign_key: true
      # When set, this Mic's schedule + sign-up timing project through the
      # CocoScout Production / Show / SignUpForm graph. When nil, the Mic's
      # own columns are the source of truth. `index: false` so we can define
      # a partial unique index below (one Mic per Production at most).
      t.references :production,   null: true,  foreign_key: true, index: false
      # Always-present columns (used as display defaults even after a
      # producer migrates).
      t.integer :status,          null: false, default: 0    # active | dormant | ended
      t.integer :format,          null: false, default: 0    # standup | music | poetry | ...
      t.integer :day_of_week                                  # 0–6 (Sun=0); nil for irregular
      t.time    :starts_local_time
      t.string  :recurrence_rule                              # RRULE; weekly is the common case
      t.date    :canceled_until                               # soft pause
      t.integer :signup_method,   null: false, default: 0    # bucket_draw | pre_signup | ...
      t.string  :signup_url
      t.integer :signup_opens_offset_minutes
      t.string  :signup_opens_at_text
      t.text    :blurb
      t.integer :spot_length_minutes
      t.integer :signup_cap
      t.integer :cost,            null: false, default: 0    # free | drink_minimum | ...
      t.integer :drink_minimum_amount_cents
      t.integer :cover_amount_cents
      t.integer :min_age
      t.jsonb   :accessibility,   null: false, default: {}
      t.string :host_summary
      t.datetime :last_verified_at
      t.bigint :last_verified_by_user_id
      t.datetime :claimed_at
      t.bigint :lead_producer_user_id
      t.timestamps
    end
    add_index :mics, :slug, unique: true
    add_index :mics, :production_id, unique: true, where: "production_id IS NOT NULL"
    add_index :mics, :status
    add_index :mics, :lead_producer_user_id

    create_table :mic_tags do |t|
      t.string  :slug, null: false
      t.string  :name, null: false
      t.timestamps
    end
    add_index :mic_tags, :slug, unique: true

    create_table :mic_taggings do |t|
      t.references :mic,      null: false, foreign_key: true
      t.references :mic_tag,  null: false, foreign_key: true
      t.timestamps
    end
    add_index :mic_taggings, %i[mic_id mic_tag_id], unique: true

    create_table :city_hubs do |t|
      t.string  :slug,    null: false
      t.string  :name,    null: false
      t.string  :state,   null: false
      t.text    :intro_markdown
      t.float   :lat
      t.float   :lng
      t.integer :default_radius_miles, null: false, default: 25
      t.string  :timezone
      # draft | active | archived
      t.integer :status,  null: false, default: 0
      t.jsonb   :featured_mic_ids, null: false, default: []
      t.timestamps
    end
    add_index :city_hubs, :slug, unique: true

    create_table :mic_edits do |t|
      t.references :mic,       null: false, foreign_key: true
      t.bigint  :editor_user_id
      t.string  :field
      t.text    :old_value
      t.text    :new_value
      # producer | suggestion | admin | migration | system
      t.integer :source, null: false, default: 0
      t.text    :note
      t.timestamps
    end
    add_index :mic_edits, :editor_user_id
  end
end
