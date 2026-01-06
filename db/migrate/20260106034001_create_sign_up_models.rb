class CreateSignUpModels < ActiveRecord::Migration[8.1]
  def change
    # SignUpForm - the main form configuration linked to a production or show
    create_table :sign_up_forms do |t|
      t.string :name, null: false
      t.text :description
      t.references :production, null: false, foreign_key: true
      t.references :show, null: true, foreign_key: true # Optional - can be production-wide or show-specific
      t.boolean :active, default: false, null: false
      t.boolean :require_login, default: false, null: false
      t.datetime :opens_at
      t.datetime :closes_at
      t.integer :slots_per_registration, default: 1, null: false # How many slots a person can sign up for
      t.timestamps
    end

    add_index :sign_up_forms, [ :production_id, :active ]

    # SignUpSlot - individual slots that can be reserved
    create_table :sign_up_slots do |t|
      t.references :sign_up_form, null: false, foreign_key: true
      t.string :name # Optional name for the slot (e.g., "Slot 1", "5 minute set", etc.)
      t.integer :position, null: false
      t.integer :capacity, default: 1, null: false # How many people can register for this slot
      t.boolean :is_held, default: false, null: false # Whether this slot is held/reserved by admin
      t.string :held_reason # Why the slot is held (e.g., "Reserved for host", "Equipment break")
      t.timestamps
    end

    add_index :sign_up_slots, [ :sign_up_form_id, :position ]

    # SignUpRegistration - a person's registration for a specific slot
    create_table :sign_up_registrations do |t|
      t.references :sign_up_slot, null: false, foreign_key: true
      t.references :person, null: true, foreign_key: true # Optional if guest registration allowed
      t.string :guest_name # For non-logged-in registrations
      t.string :guest_email # For non-logged-in registrations
      t.integer :position, null: false # Position within the slot (for slots with capacity > 1)
      t.string :status, default: "confirmed", null: false # confirmed, waitlisted, cancelled
      t.datetime :registered_at, null: false
      t.datetime :cancelled_at
      t.timestamps
    end

    add_index :sign_up_registrations, [ :sign_up_slot_id, :position ]
    add_index :sign_up_registrations, [ :sign_up_slot_id, :person_id ], unique: true, where: "person_id IS NOT NULL AND status != 'cancelled'", name: "idx_sign_up_regs_slot_person_unique"
    add_index :sign_up_registrations, :person_id, where: "person_id IS NOT NULL", name: "idx_sign_up_regs_person"

    # SignUpFormHoldout - configuration for automatically holding slots
    create_table :sign_up_form_holdouts do |t|
      t.references :sign_up_form, null: false, foreign_key: true
      t.string :holdout_type, null: false # 'first_n', 'last_n', 'every_n'
      t.integer :holdout_value, null: false # The N value for the holdout type
      t.string :reason # Optional reason shown for held slots
      t.timestamps
    end

    add_index :sign_up_form_holdouts, [ :sign_up_form_id, :holdout_type ], unique: true
  end
end
