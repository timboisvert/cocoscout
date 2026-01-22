# frozen_string_literal: true

class MakePayoutSchemesOrganizationLevel < ActiveRecord::Migration[8.0]
  def change
    # Add organization_id to payout_schemes
    add_reference :payout_schemes, :organization, null: true, foreign_key: true

    # Make production_id nullable (existing records will keep their production_id)
    change_column_null :payout_schemes, :production_id, true

    # Add index for organization-level queries
    add_index :payout_schemes, [ :organization_id, :is_default ],
              name: "index_payout_schemes_on_organization_id_and_is_default"

    # Backfill organization_id for existing schemes based on their production
    reversible do |dir|
      dir.up do
        execute <<-SQL.squish
          UPDATE payout_schemes
          SET organization_id = productions.organization_id
          FROM productions
          WHERE payout_schemes.production_id = productions.id
            AND payout_schemes.organization_id IS NULL
        SQL
      end
    end

    # Add check constraint: must have either organization_id or production_id
    # (production_id implies organization_id, but org-level schemes don't need production_id)
    # Note: We don't enforce this at DB level since existing schemes may not have org_id yet
  end
end
