# frozen_string_literal: true

# The demo organization (Starlight Community Theater, its seeder and the
# superadmin Demo Users page) is gone (Tim, 2026-10-28: "we never really used
# it"). The App Review accounts keep their demo.cocoscout.com emails, which
# superadmin's counts still leave out.
class RemoveDemoOrganizationFeature < ActiveRecord::Migration[8.1]
  def up
    drop_table :demo_users
    remove_column :organizations, :is_demo
  end

  def down
    add_column :organizations, :is_demo, :boolean, default: false, null: false
    create_table :demo_users do |t|
      t.string :email, null: false
      t.string :name
      t.text :notes
      t.references :created_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.timestamps
    end
    add_index :demo_users, :email, unique: true
  end
end
