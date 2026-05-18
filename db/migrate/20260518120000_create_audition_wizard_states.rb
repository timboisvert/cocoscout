# frozen_string_literal: true

class CreateAuditionWizardStates < ActiveRecord::Migration[8.1]
  def change
    create_table :audition_wizard_states do |t|
      t.references :production, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.jsonb :state, null: false, default: {}
      t.timestamps
    end
    add_index :audition_wizard_states, [ :production_id, :user_id ], unique: true, name: "idx_audition_wizard_states_on_production_user"
  end
end
