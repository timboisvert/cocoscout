# frozen_string_literal: true

# Tax collected on a course registration (TaxCalculator, money kind
# "courses"). amount_cents stays the course's price before tax: fees, the
# instructor split and the payout calc keep working on it unchanged.
class AddTaxCentsToCourseRegistrations < ActiveRecord::Migration[8.1]
  def change
    add_column :course_registrations, :tax_cents, :integer, null: false, default: 0
  end
end
