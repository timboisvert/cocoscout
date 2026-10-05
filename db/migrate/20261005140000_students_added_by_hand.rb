# frozen_string_literal: true

# A manager can add a student to a course by hand: free, or paid another way
# (cash, check, Zelle, Venmo, other). The registration says how it came and
# who added it, and remembers which sessions the student attended.
class StudentsAddedByHand < ActiveRecord::Migration[8.1]
  def change
    add_column :course_registrations, :channel, :string, null: false, default: "online"
    add_column :course_registrations, :paid_via, :string
    add_reference :course_registrations, :added_by, null: true, foreign_key: { to_table: :users }
    add_column :course_registrations, :attended_show_ids, :jsonb, null: false, default: []
  end
end
