class MakeAuditionCycleClosesAtNullable < ActiveRecord::Migration[8.1]
  def change
    change_column_null :audition_cycles, :closes_at, true
  end
end
