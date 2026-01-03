class CreateEmailTemplates < ActiveRecord::Migration[8.1]
  def change
    create_table :email_templates do |t|
      t.string :key, null: false
      t.string :name, null: false
      t.string :subject, null: false
      t.text :body, null: false
      t.text :description
      t.jsonb :available_variables, default: []
      t.string :category
      t.boolean :active, default: true

      t.timestamps
    end

    add_index :email_templates, :key, unique: true
    add_index :email_templates, :category
    add_index :email_templates, :active
  end
end
