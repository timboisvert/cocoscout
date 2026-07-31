# frozen_string_literal: true

# Per-run instructor split for STANDALONE (no-contract) courses: each instructor
# on a run can be paid a % of net revenue or a flat amount, so a contract-free
# course still pays its instructor through the Stripe course payout run.
# (Contract-based courses continue to use the contract's terms.)
class AddPayoutSplitToCourseOfferingInstructors < ActiveRecord::Migration[8.1]
  def change
    add_column :course_offering_instructors, :payout_type, :string, default: "none", null: false
    add_column :course_offering_instructors, :payout_percentage, :decimal, precision: 5, scale: 2
    add_column :course_offering_instructors, :payout_cents, :integer
  end
end
