class CreateJoinTablePeopleProductionCompanies < ActiveRecord::Migration[8.1]
  def change
    create_join_table :people, :production_companies do |t|
      t.index [ :person_id, :production_company_id ]
      t.index [ :production_company_id, :person_id ]
    end
  end
end
