class AddPayoutScheduleToOrganizations < ActiveRecord::Migration[8.1]
  def change
    add_column :organizations, :payout_schedule, :string, null: false, default: "manual"
    add_column :organizations, :payout_schedule_day, :integer
    add_column :organizations, :payout_funding_method, :string, null: false, default: "ach"
    add_column :organizations, :last_auto_payout_on, :date
  end
end
