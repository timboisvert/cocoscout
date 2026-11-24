# frozen_string_literal: true

# CocoScout sends its own failed-payment email and yearly renewal reminder
# (Tim, 2026-11-24: Stripe's own subscription emails are switched off). Each
# is sent once: a bill remembers which failed attempt it emailed about, and
# an organization remembers which renewal date it was reminded of.
class AddBillingNoticeMarks < ActiveRecord::Migration[8.1]
  def change
    add_column :billing_invoices, :failure_emailed_for, :string
    add_column :organizations, :renewal_reminded_for, :datetime
  end
end
