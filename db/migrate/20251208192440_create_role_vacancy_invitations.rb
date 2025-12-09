class CreateRoleVacancyInvitations < ActiveRecord::Migration[8.1]
  def change
    create_table :role_vacancy_invitations do |t|
      t.references :role_vacancy, null: false, foreign_key: true
      t.references :person, null: false, foreign_key: true
      t.string :token, null: false
      t.datetime :invited_at
      t.datetime :claimed_at
      t.string :email_subject
      t.text :email_body

      t.timestamps
    end

    add_index :role_vacancy_invitations, :token, unique: true
    add_index :role_vacancy_invitations, [ :role_vacancy_id, :person_id ], unique: true, name: "idx_vacancy_invitations_on_vacancy_and_person"
  end
end
