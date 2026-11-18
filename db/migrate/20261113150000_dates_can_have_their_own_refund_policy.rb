# frozen_string_literal: true

# A date's own refund policy (Tim, 2026-11-13: "find other things that I
# should be able to override at a show level that I currently can't"). The
# box office sets one, a production could set its own, and a date could only
# follow. The same four columns the production has; blank follows the
# production, then the box office (RefundPolicy.for).
class DatesCanHaveTheirOwnRefundPolicy < ActiveRecord::Migration[8.1]
  def change
    add_column :ticket_listings, :refund_policy, :string
    add_column :ticket_listings, :refund_window_hours, :integer
    add_column :ticket_listings, :refund_fees, :boolean
    add_column :ticket_listings, :refund_policy_note, :text
  end
end
