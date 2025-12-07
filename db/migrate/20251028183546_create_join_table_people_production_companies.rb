# frozen_string_literal: true

class CreateJoinTablePeopleProductionCompanies < ActiveRecord::Migration[8.1]
  def change
    create_join_table :people, :production_companies do |t|
      t.index %i[person_id production_company_id]
      t.index %i[production_company_id person_id]
    end
  end
end
