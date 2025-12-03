class CreateCastEmailDrafts < ActiveRecord::Migration[8.1]
  def change
    create_table :cast_email_drafts do |t|
      t.references :show, null: false, foreign_key: true
      t.string :title

      t.timestamps
    end
  end
end
