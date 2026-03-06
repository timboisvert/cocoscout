class AddIsDemoToOrganizations < ActiveRecord::Migration[8.1]
  def change
    add_column :organizations, :is_demo, :boolean, default: false, null: false

    reversible do |dir|
      dir.up do
        execute <<-SQL
          UPDATE organizations SET is_demo = true WHERE name LIKE '%(Demo%' OR name LIKE '%(Demo)%'
        SQL
      end
    end
  end
end
