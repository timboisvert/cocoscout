# frozen_string_literal: true

# Store the Stripe refund id on a refunded registration so a course can trace a
# refund all the way back to the exact Stripe refund object, not just "refunded".
class AddStripeRefundIdToCourseRegistrations < ActiveRecord::Migration[8.1]
  def change
    add_column :course_registrations, :stripe_refund_id, :string
  end
end
