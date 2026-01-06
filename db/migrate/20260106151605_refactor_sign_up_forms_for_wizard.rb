class RefactorSignUpFormsForWizard < ActiveRecord::Migration[8.1]
  def change
    # === Add new columns to sign_up_forms ===

    # Scope & Targeting
    add_column :sign_up_forms, :scope, :string, default: "single_event", null: false
    add_column :sign_up_forms, :event_matching, :string, default: "all"
    add_column :sign_up_forms, :event_type_filter, :jsonb, default: []
    add_column :sign_up_forms, :url_slug, :string

    # Slot Template (for generating slots on instances)
    add_column :sign_up_forms, :slot_generation_mode, :string, default: "numbered"
    add_column :sign_up_forms, :slot_count, :integer, default: 10
    add_column :sign_up_forms, :slot_prefix, :string, default: "Slot"
    add_column :sign_up_forms, :slot_capacity, :integer, default: 1
    add_column :sign_up_forms, :slot_start_time, :string
    add_column :sign_up_forms, :slot_interval_minutes, :integer
    add_column :sign_up_forms, :slot_names, :jsonb, default: []

    # Registration Rules
    add_column :sign_up_forms, :registrations_per_person, :integer, default: 1
    add_column :sign_up_forms, :slot_selection_mode, :string, default: "choose"
    add_column :sign_up_forms, :allow_edit, :boolean, default: true
    add_column :sign_up_forms, :allow_cancel, :boolean, default: true
    add_column :sign_up_forms, :edit_cutoff_hours, :integer, default: 24
    add_column :sign_up_forms, :cancel_cutoff_hours, :integer, default: 2

    # Schedule Rules
    add_column :sign_up_forms, :schedule_mode, :string, default: "relative"
    add_column :sign_up_forms, :opens_days_before, :integer, default: 7
    add_column :sign_up_forms, :closes_hours_before, :integer, default: 2

    add_index :sign_up_forms, :url_slug
    add_index :sign_up_forms, [ :production_id, :scope ]

    # === Create sign_up_form_instances table ===
    create_table :sign_up_form_instances do |t|
      t.references :sign_up_form, null: false, foreign_key: true
      t.references :show, null: false, foreign_key: true
      t.datetime :opens_at
      t.datetime :closes_at
      t.datetime :edit_cutoff_at
      t.string :status, default: "scheduled", null: false

      t.timestamps
    end

    add_index :sign_up_form_instances, [ :sign_up_form_id, :show_id ], unique: true
    add_index :sign_up_form_instances, [ :show_id, :status ]

    # === Create join table for manual show selection ===
    create_table :sign_up_form_shows do |t|
      t.references :sign_up_form, null: false, foreign_key: true
      t.references :show, null: false, foreign_key: true

      t.timestamps
    end

    add_index :sign_up_form_shows, [ :sign_up_form_id, :show_id ], unique: true

    # === Update sign_up_slots to belong to instances ===
    # Add instance reference (nullable initially for migration)
    add_reference :sign_up_slots, :sign_up_form_instance, foreign_key: true

    # We'll migrate existing slots in a data migration after this
  end
end
