# frozen_string_literal: true

# Mailing lists (V1.1, Tim 2026-10-23; docs/production_mode_v2_plan.md §11).
# A Pro organization keeps its followers in lists, segments them by what they
# bought, and emails them; a producer the organization shares a list with sees
# it in My Followers. The word is "followers", never fans or subscribers.
class CreateMailingLists < ActiveRecord::Migration[8.1]
  def change
    # One row per person per organization: Stars & Garters' Jane and Babs'
    # Jane are two rows, each with its own consent and unsubscribe state.
    create_table :followers do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :email, null: false
      t.string :name
      t.references :person, foreign_key: true
      t.string :status, null: false, default: "subscribed"
      t.datetime :consented_at
      t.datetime :unsubscribed_at
      t.string :unsubscribe_token, null: false
      t.datetime :last_emailed_at
      t.timestamps
    end
    add_index :followers, [ :organization_id, :email ], unique: true
    add_index :followers, :unsubscribe_token, unique: true

    create_table :mailing_lists do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :name, null: false
      t.string :kind, null: false, default: "group"
      # The box's words at checkout, e.g. "Send me news about Dan Feltey's shows".
      t.string :checkout_words
      t.datetime :archived_at
      t.timestamps
    end
    add_index :mailing_lists, :organization_id, unique: true, where: "kind = 'main'", name: "index_mailing_lists_one_main_per_org"

    create_table :mailing_list_productions do |t|
      t.references :mailing_list, null: false, foreign_key: true
      t.references :production, null: false, foreign_key: true
      t.timestamps
    end
    add_index :mailing_list_productions, [ :mailing_list_id, :production_id ], unique: true, name: "index_mailing_list_productions_unique"

    create_table :mailing_list_memberships do |t|
      t.references :mailing_list, null: false, foreign_key: true
      t.references :follower, null: false, foreign_key: true
      t.timestamps
    end
    add_index :mailing_list_memberships, [ :mailing_list_id, :follower_id ], unique: true, name: "index_mailing_list_memberships_unique"

    create_table :mailing_list_shares do |t|
      t.references :mailing_list, null: false, foreign_key: true
      t.references :person, null: false, foreign_key: true
      t.references :granted_by, foreign_key: { to_table: :users }
      t.datetime :granted_at, null: false
      t.timestamps
    end
    add_index :mailing_list_shares, [ :mailing_list_id, :person_id ], unique: true

    # Every way a follower arrived or bought: "where they came from", and what
    # segments are built from.
    create_table :follower_sources do |t|
      t.references :follower, null: false, foreign_key: true
      t.string :kind, null: false
      t.references :production, foreign_key: true
      t.references :show, foreign_key: true
      t.references :ticket_order, foreign_key: true
      t.references :mailing_list, foreign_key: true
      t.references :added_by_person, foreign_key: { to_table: :people }
      t.datetime :occurred_at, null: false
      t.timestamps
    end
    add_index :follower_sources, [ :follower_id, :ticket_order_id ], unique: true, where: "ticket_order_id IS NOT NULL",
                                                                       name: "index_follower_sources_one_per_order"

    create_table :segments do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :name, null: false
      t.jsonb :rule, null: false, default: {}
      t.timestamps
    end

    create_table :follower_emails do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :subject
      t.string :preheader
      t.string :status, null: false, default: "draft"
      # { "list_ids" => [..], "segment_ids" => [..] }
      t.jsonb :targets, null: false, default: {}
      # Shows drawn as blocks after the words, in order.
      t.jsonb :show_ids, null: false, default: []
      t.references :created_by, foreign_key: { to_table: :users }
      t.references :sent_by, foreign_key: { to_table: :users }
      t.datetime :sent_at
      t.integer :recipient_count, null: false, default: 0
      t.timestamps
    end

    create_table :follower_email_deliveries do |t|
      t.references :follower_email, null: false, foreign_key: true
      t.references :follower, null: false, foreign_key: true
      t.string :email, null: false
      t.string :status, null: false, default: "queued"
      t.string :mailgun_message_id
      t.datetime :sent_at
      t.datetime :delivered_at
      t.datetime :failed_at
      t.text :error
      t.timestamps
    end
    add_index :follower_email_deliveries, [ :follower_email_id, :follower_id ], unique: true, name: "index_follower_email_deliveries_unique"
    add_index :follower_email_deliveries, :mailgun_message_id
    add_index :follower_email_deliveries, :sent_at

    # Platform-wide: a hard bounce or a spam complaint stops every
    # organization from mailing that address.
    create_table :email_suppressions do |t|
      t.string :email, null: false
      t.string :reason, null: false
      t.string :source
      t.timestamps
    end
    add_index :email_suppressions, :email, unique: true

    # The email look (logo is Organization#logo).
    change_table :organizations, bulk: true do |t|
      t.string :email_accent_color
      t.string :email_footer_line
      t.string :email_website_url
      t.string :email_instagram
      t.string :email_mailing_address
    end

    # Checkout's boxes.
    change_table :ticketing_profiles, bulk: true do |t|
      t.boolean :follow_at_checkout, null: false, default: true
      t.boolean :follow_boxes_ticked, null: false, default: true
      t.string :follow_main_words
    end

    # Which lists the buyer ticked, kept until the money arrives.
    add_column :ticket_orders, :follow_list_ids, :jsonb, null: false, default: []
  end
end
