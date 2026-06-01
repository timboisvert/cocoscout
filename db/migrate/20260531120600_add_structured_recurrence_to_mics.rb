# frozen_string_literal: true

# Replace the freeform `recurrence_rule` text field with structured
# columns so we can actually compute concrete dates:
#
#  * recurrence_pattern (enum, default weekly)
#  * recurrence_interval (integer, default 1) — "every N units"; only
#    used for `every_n_weeks` and `every_n_months`
#  * recurrence_nth_week (integer, 1..5 or -1 for last) — used for
#    monthly_nth_weekday
#  * recurrence_day_of_month (integer 1..31) — used for
#    monthly_day_of_month
#  * recurrence_anchor_date (date) — fixes parity for biweekly/Nth-week
#    when set; otherwise we anchor on the first computed date
class AddStructuredRecurrenceToMics < ActiveRecord::Migration[8.1]
  def change
    # 0 weekly | 1 biweekly | 2 monthly_nth_weekday | 3 monthly_day_of_month
    add_column :mics, :recurrence_pattern,         :integer, null: false, default: 0
    add_column :mics, :recurrence_interval,        :integer, null: false, default: 1
    add_column :mics, :recurrence_nth_week,        :integer
    add_column :mics, :recurrence_day_of_month,    :integer
    add_column :mics, :recurrence_anchor_date,     :date
  end
end
