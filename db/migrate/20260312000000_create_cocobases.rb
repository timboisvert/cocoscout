# frozen_string_literal: true

class CreateCocobases < ActiveRecord::Migration[8.1]
  def change
    # Template: one per production, defines default fields and auto-generation rules
    create_table :cocobase_templates do |t|
      t.references :production, null: false, foreign_key: true, index: { unique: true }
      t.boolean :enabled, default: false, null: false
      t.text :event_types # Serialized YAML array of event type keys
      t.integer :default_deadline_days, default: 7, null: false
      t.timestamps
    end

    # Template fields: field definitions on the template
    create_table :cocobase_template_fields do |t|
      t.references :cocobase_template, null: false, foreign_key: true
      t.string :label, null: false
      t.text :description
      t.string :field_type, null: false # text, textarea, file_upload, url, yesno
      t.boolean :required, default: false, null: false
      t.integer :position, default: 0, null: false
      t.text :config # Serialized JSON for type-specific config
      t.timestamps
    end

    add_index :cocobase_template_fields, [ :cocobase_template_id, :position ],
              name: "idx_cocobase_tmpl_fields_on_tmpl_position"

    # Per-show instance
    create_table :cocobases do |t|
      t.references :show, null: false, foreign_key: true, index: { unique: true }
      t.references :cocobase_template, foreign_key: true # nullable - null if manually created
      t.datetime :deadline
      t.string :status, default: "open", null: false
      t.timestamps
    end

    # Per-show field definitions (copied from template, customizable per show)
    create_table :cocobase_fields do |t|
      t.references :cocobase, null: false, foreign_key: true
      t.string :label, null: false
      t.text :description
      t.string :field_type, null: false
      t.boolean :required, default: false, null: false
      t.integer :position, default: 0, null: false
      t.text :config
      t.timestamps
    end

    add_index :cocobase_fields, [ :cocobase_id, :position ]

    # Per-person/group submission record
    create_table :cocobase_submissions do |t|
      t.references :cocobase, null: false, foreign_key: true
      t.string :submittable_type, null: false
      t.bigint :submittable_id, null: false
      t.string :status, default: "pending", null: false
      t.datetime :submitted_at
      t.timestamps
    end

    add_index :cocobase_submissions, [ :submittable_type, :submittable_id ],
              name: "idx_cocobase_submissions_on_submittable"
    add_index :cocobase_submissions, [ :cocobase_id, :submittable_type, :submittable_id ],
              unique: true, name: "idx_cocobase_submissions_unique"

    # Individual field responses
    create_table :cocobase_answers do |t|
      t.references :cocobase_submission, null: false, foreign_key: true
      t.references :cocobase_field, null: false, foreign_key: true
      t.text :value
      t.timestamps
    end

    add_index :cocobase_answers, [ :cocobase_submission_id, :cocobase_field_id ],
              unique: true, name: "idx_cocobase_answers_unique"
  end
end
