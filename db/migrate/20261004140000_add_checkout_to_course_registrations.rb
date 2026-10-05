# frozen_string_literal: true

# A course registration now starts life as the buyer's ten-minute hold on a
# spot (as a ticket order does), paid on our own checkout page: a secret
# token names it, expires_at is the hold, and a lapsed hold becomes
# "expired". The Redis spot hold goes.
class AddCheckoutToCourseRegistrations < ActiveRecord::Migration[8.1]
  def change
    add_column :course_registrations, :token, :string
    add_column :course_registrations, :expires_at, :datetime
    add_column :course_registrations, :stripe_charge_id, :string
    add_index :course_registrations, :token, unique: true
    add_index :course_registrations, :expires_at, where: "status = 'pending'"

    # One live registration per person and course; an expired hold doesn't count.
    remove_index :course_registrations, name: "idx_course_registrations_active_unique"
    add_index :course_registrations, [ :course_offering_id, :person_id ], unique: true,
              where: "status NOT IN ('cancelled', 'refunded', 'expired')", name: "idx_course_registrations_active_unique"
  end
end
