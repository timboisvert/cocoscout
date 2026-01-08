class AddQueueSupportToSignUpForms < ActiveRecord::Migration[8.1]
  def change
    # Queue configuration on sign_up_forms
    add_column :sign_up_forms, :queue_limit, :integer, null: true  # nil = unlimited
    add_column :sign_up_forms, :queue_carryover, :boolean, default: false, null: false

    # Optional role linking on sign_up_slots (for casting integration)
    add_reference :sign_up_slots, :role, null: true, foreign_key: true

    # Queue support on sign_up_registrations
    # Make sign_up_slot_id nullable (queued registrations don't have a slot yet)
    change_column_null :sign_up_registrations, :sign_up_slot_id, true

    # Add instance reference for queued registrations
    add_reference :sign_up_registrations, :sign_up_form_instance, null: true, foreign_key: true

    # Add index for finding queued registrations by instance
    add_index :sign_up_registrations, [ :sign_up_form_instance_id, :status ], name: "idx_registrations_instance_status"
  end
end
