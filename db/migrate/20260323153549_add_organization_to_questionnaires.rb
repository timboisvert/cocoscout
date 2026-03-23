class AddOrganizationToQuestionnaires < ActiveRecord::Migration[8.1]
  def change
    add_reference :questionnaires, :organization, null: true, foreign_key: true

    # Backfill organization_id from production
    reversible do |dir|
      dir.up do
        execute <<~SQL
          UPDATE questionnaires
          SET organization_id = (
            SELECT productions.organization_id
            FROM productions
            WHERE productions.id = questionnaires.production_id
          )
          WHERE questionnaires.production_id IS NOT NULL
        SQL
      end
    end

    change_column_null :questionnaires, :organization_id, false
  end
end
