class AddAffectedShowsToRoleVacancies < ActiveRecord::Migration[8.1]
  def change
    # Create join table for role_vacancies to track multiple affected shows
    create_table :role_vacancy_shows do |t|
      t.references :role_vacancy, null: false, foreign_key: true
      t.references :show, null: false, foreign_key: true
      t.timestamps
    end

    # Add unique index to prevent duplicates
    add_index :role_vacancy_shows, [ :role_vacancy_id, :show_id ], unique: true
  end
end
