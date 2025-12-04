class DropNotifyMes < ActiveRecord::Migration[8.1]
  def up
    drop_table :notify_mes
  end

  def down
    create_table :notify_mes do |t|
      t.string :email
      t.timestamps
    end
  end
end
