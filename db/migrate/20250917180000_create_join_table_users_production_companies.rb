# frozen_string_literal: true

class CreateJoinTableUsersProductionCompanies < ActiveRecord::Migration[7.0]
  def change
    create_join_table :users, :production_companies do |t|
      t.index :user_id
      t.index :production_company_id
    end
  end
end
