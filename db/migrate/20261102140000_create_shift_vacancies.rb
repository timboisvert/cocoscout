# frozen_string_literal: true

# A shift someone said they can't make, and what became of it: the staffing
# counterpart of role_vacancies (Tim, 2026-11-02). The declined
# shift_assignments row stays as the schedule's picture of the hole; this is
# the work around it, with invitations the way role_vacancy_invitations are.
class CreateShiftVacancies < ActiveRecord::Migration[8.1]
  class Vacancy < ActiveRecord::Base
    self.table_name = "shift_vacancies"
  end

  def up
    create_table :shift_vacancies do |t|
      t.references :shift, null: false, foreign_key: true
      t.references :vacated_by, null: false, foreign_key: { to_table: :people }
      t.datetime :vacated_at, null: false
      t.text :reason
      t.string :status, null: false, default: "open"
      t.references :filled_by, foreign_key: { to_table: :people }
      t.datetime :filled_at
      t.references :closed_by, foreign_key: { to_table: :users }
      t.datetime :closed_at
      t.timestamps
    end
    add_index :shift_vacancies, [ :shift_id, :status ]
    add_index :shift_vacancies, [ :shift_id, :vacated_by_id ], unique: true,
              where: "status IN ('open','finding_replacement')", name: "idx_shift_vacancies_one_active_per_person"

    create_table :shift_vacancy_invitations do |t|
      t.references :shift_vacancy, null: false, foreign_key: true
      t.references :person, null: false, foreign_key: true
      t.string :token, null: false
      t.datetime :invited_at
      t.datetime :claimed_at
      t.datetime :declined_at
      t.string :email_subject
      t.text :email_body
      t.timestamps
    end
    add_index :shift_vacancy_invitations, :token, unique: true
    add_index :shift_vacancy_invitations, [ :shift_vacancy_id, :person_id ], unique: true

    # Every decline still standing on an upcoming shift becomes an open vacancy,
    # quietly: insert_all fires no notice.
    rows = select_all(<<~SQL)
      SELECT a.shift_id, a.person_id, a.declined_at, a.decline_reason
      FROM shift_assignments a JOIN shifts s ON s.id = a.shift_id
      WHERE a.declined_at IS NOT NULL AND s.ends_at >= NOW()
    SQL
    now = Time.current
    if rows.any?
      Vacancy.insert_all(rows.map { |r|
        { shift_id: r["shift_id"], vacated_by_id: r["person_id"], vacated_at: r["declined_at"] || now,
          reason: r["decline_reason"], status: "open", created_at: now, updated_at: now }
      })
    end
  end

  def down
    drop_table :shift_vacancy_invitations
    drop_table :shift_vacancies
  end
end
