# frozen_string_literal: true

# Visual asset specifications (Tim, 2026-11-19): the images and words an
# organization expects every production to have (asset_specs), what each
# production has for them plus any files of its own (production_assets), and
# the one link that asks someone outside for them (asset_requests).
class VisualAssetSpecifications < ActiveRecord::Migration[8.1]
  def change
    create_table :asset_specs do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :name, null: false
      t.string :kind, null: false, default: "image"
      t.string :builtin
      t.integer :position, null: false, default: 0
      t.boolean :required, null: false, default: true
      t.datetime :archived_at
      t.integer :width
      t.integer :height
      t.integer :dpi
      t.string :formats, array: true, null: false, default: []
      t.integer :max_megabytes, null: false, default: 10
      t.integer :max_length
      t.string :used_for
      t.text :guidance
      t.timestamps
    end
    add_index :asset_specs, %i[organization_id position]
    add_index :asset_specs, %i[organization_id builtin], unique: true, where: "builtin IS NOT NULL"

    create_table :asset_requests do |t|
      t.references :production, null: false, foreign_key: true
      t.string :token, null: false
      t.references :created_by, foreign_key: { to_table: :users }
      t.jsonb :recipients, null: false, default: []
      t.string :subject
      t.text :message
      t.boolean :allow_replace, null: false, default: true
      t.datetime :sent_at
      t.datetime :turned_off_at
      t.datetime :last_activity_at
      t.datetime :notified_through_at
      t.datetime :completed_notified_at
      t.timestamps
    end
    add_index :asset_requests, :token, unique: true

    create_table :production_assets do |t|
      t.references :production, null: false, foreign_key: true
      t.references :asset_spec, foreign_key: true
      t.references :asset_request, foreign_key: true
      t.string :name
      t.text :text_value
      t.integer :width
      t.integer :height
      t.references :uploaded_by_user, foreign_key: { to_table: :users }
      t.string :uploaded_by_name
      t.string :last_change
      t.datetime :changed_at
      t.timestamps
    end
    add_index :production_assets, %i[production_id asset_spec_id], unique: true, where: "asset_spec_id IS NOT NULL",
              name: "index_production_assets_one_per_spec"
  end
end
