class CreateEmailGroups < ActiveRecord::Migration[8.1]
  def change
    create_table :email_groups do |t|
      t.references :production, null: false, foreign_key: true
      t.string :group_id
      t.string :name
      t.text :email_template

      t.timestamps
    end
  end
end
