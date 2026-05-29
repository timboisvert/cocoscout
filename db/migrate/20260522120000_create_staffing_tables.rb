# frozen_string_literal: true

# Staffing module — org-level house staffing (separate from cast/role assignments
# on Show). Lets orgs define house roles (bartender, FOH, tech, ...), maintain
# a staff roster with per-person role qualifications, generate shifts from the
# show schedule, and assign staff to shifts.
class CreateStaffingTables < ActiveRecord::Migration[8.1]
  def change
    create_table :house_roles do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :location, null: true, foreign_key: true # optional per-venue override
      t.string :name, null: false
      t.integer :default_required_count, null: false, default: 1
      # Offsets in minutes from "first show start" and "last show end" of the day.
      # Negative offsets shift earlier; positive shift later. Examples:
      #   default_start_offset_minutes = -60 → start 60 min before first show
      #   default_end_offset_minutes   =  60 → end   60 min after  last show
      t.integer :default_start_offset_minutes, null: false, default: -60
      t.integer :default_end_offset_minutes, null: false, default: 60
      t.integer :position, null: false, default: 0
      t.datetime :archived_at
      t.timestamps
    end
    add_index :house_roles, [ :organization_id, :archived_at, :position ], name: "idx_house_roles_org_position"

    create_table :organization_staff_members do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :person, null: false, foreign_key: true
      t.datetime :archived_at
      t.timestamps
    end
    add_index :organization_staff_members, [ :organization_id, :person_id ], unique: true, name: "idx_org_staff_members_unique"

    create_table :staff_role_qualifications do |t|
      t.references :organization_staff_member, null: false, foreign_key: true, index: { name: "idx_staff_role_qual_member" }
      t.references :house_role, null: false, foreign_key: true
      t.timestamps
    end
    add_index :staff_role_qualifications, [ :organization_staff_member_id, :house_role_id ], unique: true, name: "idx_staff_role_qual_unique"

    create_table :shifts do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :house_role, null: false, foreign_key: true
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false
      t.integer :required_count, null: false, default: 1
      # coverage_mode enum: needs_assignment(0), covered_by_renter(1), not_needed(2)
      t.integer :coverage_mode, null: false, default: 0
      # Polymorphic source: Show, SpaceRental, or NULL for free-standing shifts
      t.string :source_type
      t.bigint :source_id
      # Used when coverage_mode = covered_by_renter and the source is null or
      # we need a manual override (e.g. show has multiple potential renters).
      t.string :renter_name
      t.text :notes
      t.timestamps
    end
    add_index :shifts, [ :organization_id, :starts_at ]
    add_index :shifts, [ :source_type, :source_id ]
    # Prevent the "Generate shifts" action from duplicating shifts on rerun
    add_index :shifts, [ :house_role_id, :source_type, :source_id, :starts_at, :ends_at ],
              unique: true, name: "idx_shifts_no_dupe"

    create_table :shift_assignments do |t|
      t.references :shift, null: false, foreign_key: true
      t.references :person, null: false, foreign_key: true
      t.integer :position, null: false, default: 1 # ordering when required_count > 1
      t.datetime :notified_at
      t.datetime :accepted_at
      t.datetime :declined_at
      t.timestamps
    end
    add_index :shift_assignments, [ :shift_id, :person_id ], unique: true, name: "idx_shift_assignments_unique"
  end
end
