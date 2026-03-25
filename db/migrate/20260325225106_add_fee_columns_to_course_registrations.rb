class AddFeeColumnsToCourseRegistrations < ActiveRecord::Migration[8.1]
  def change
    add_column :course_registrations, :stripe_fee_cents, :integer
    add_column :course_registrations, :cocoscout_fee_cents, :integer
  end
end
