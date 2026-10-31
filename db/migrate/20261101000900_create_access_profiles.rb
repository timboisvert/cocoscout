# frozen_string_literal: true

# Accessibility (accessibility plan §1, §2, §4; V1.4): a location's and room's
# answers feature by feature, who to ask, room-only facts, each performance's
# access services and content notes, and a buyer's access needs on an order.
class CreateAccessProfiles < ActiveRecord::Migration[8.1]
  def change
    create_table :access_answers do |t|
      t.references :owner, polymorphic: true, null: false
      t.string :feature_key, null: false
      t.string :answer, null: false
      t.string :note
      t.references :updated_by, foreign_key: { to_table: :users }
      t.timestamps
      t.index %i[owner_type owner_id feature_key], unique: true
    end

    add_column :locations, :access_email, :string
    add_column :locations, :access_phone, :string
    add_column :location_spaces, :wheelchair_spaces, :integer
    add_column :location_spaces, :wheelchair_spaces_note, :string
    add_column :location_spaces, :stage_access, :string
    add_column :location_spaces, :floor_label, :string

    create_table :show_access_services do |t|
      t.references :show, null: false, foreign_key: true
      t.string :service, null: false
      t.string :detail
      t.timestamps
      t.index %i[show_id service], unique: true
    end

    add_column :productions, :content_note_keys, :jsonb, null: false, default: []
    add_column :productions, :content_note_text, :text
    add_column :shows, :content_note_keys, :jsonb, null: false, default: []
    add_column :shows, :content_note_text, :text

    create_table :ticket_order_access_requests do |t|
      t.references :ticket_order, null: false, foreign_key: true, index: { unique: true }
      t.jsonb :request_keys, null: false, default: []
      t.text :note
      t.timestamps
    end
  end
end
