class AddGuestAndProductionFeatures < ActiveRecord::Migration[8.1]
  def change
    # Guest assignment columns for show_person_role_assignments
    # When assignable_id is nil but guest fields are present, it's a guest assignment
    add_column :show_person_role_assignments, :guest_name, :string
    add_column :show_person_role_assignments, :guest_email, :string

    # Production feature flags - all default to true for existing productions
    add_column :productions, :has_talent_pool, :boolean, default: true, null: false
    add_column :productions, :has_roles, :boolean, default: true, null: false
    add_column :productions, :has_sign_up_slots, :boolean, default: false, null: false
    add_column :productions, :has_auditions, :boolean, default: true, null: false
  end
end
