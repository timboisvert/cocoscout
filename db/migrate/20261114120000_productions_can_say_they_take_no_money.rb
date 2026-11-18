# frozen_string_literal: true

# A production that never takes money (Tim, 2026-11-14: "an open mic that we
# have. It never produces revenue and therefore it should always settle up
# as non-revenue"). Its shows settle as no revenue on their own, confirmed,
# unless money did come in for one.
class ProductionsCanSayTheyTakeNoMoney < ActiveRecord::Migration[8.1]
  def change
    add_column :productions, :no_revenue, :boolean, default: false, null: false
  end
end
