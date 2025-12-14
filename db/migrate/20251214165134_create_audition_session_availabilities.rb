class CreateAuditionSessionAvailabilities < ActiveRecord::Migration[8.1]
  def change
    create_table :audition_session_availabilities do |t|
      t.references :available_entity, polymorphic: true, null: false
      t.references :audition_session, null: false, foreign_key: true
      t.integer :status, default: 0

      t.timestamps
    end

    add_index :audition_session_availabilities,
              [ :available_entity_id, :available_entity_type, :audition_session_id ],
              unique: true,
              name: 'index_audition_session_avail_on_entity_and_session'
  end
end
