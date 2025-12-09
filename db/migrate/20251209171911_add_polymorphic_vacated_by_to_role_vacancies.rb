class AddPolymorphicVacatedByToRoleVacancies < ActiveRecord::Migration[8.1]
  def change
    add_column :role_vacancies, :vacated_by_type, :string

    # Set existing records to "Person" type since vacated_by_id was previously always a Person
    reversible do |dir|
      dir.up do
        execute "UPDATE role_vacancies SET vacated_by_type = 'Person' WHERE vacated_by_id IS NOT NULL"
      end
    end

    # Add index for polymorphic lookup
    add_index :role_vacancies, [:vacated_by_type, :vacated_by_id], name: "index_role_vacancies_on_vacated_by"
  end
end
