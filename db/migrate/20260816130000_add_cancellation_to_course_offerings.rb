class AddCancellationToCourseOfferings < ActiveRecord::Migration[8.1]
  def change
    # A course that isn't happening. Cancelling refunds every paid registrant,
    # cancels the sessions and dissolves the payout — see CourseCancellationJob.
    # The status itself is the string enum's new "cancelled" value.
    add_column :course_offerings, :cancelled_at, :datetime
    add_reference :course_offerings, :cancelled_by_user, foreign_key: { to_table: :users }, null: true
    # The cancelling manager's choice to tell registrants; a retry reads it back
    # so a second pass behaves like the first.
    add_column :course_offerings, :cancellation_notify_registrants, :boolean, default: true, null: false
  end
end
