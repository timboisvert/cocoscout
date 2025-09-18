class DropProductionCompaniesUsers < ActiveRecord::Migration[7.0]
  def up
    drop_table :production_companies_users, if_exists: true
  end

  def down
    create_table :production_companies_users, id: false do |t|
      t.references :production_company, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
    end
    add_index :production_companies_users, [ :production_company_id, :user_id ], unique: true, name: 'index_production_companies_users_on_company_and_user'
  end
end
