class CreatePayoutSchemeDefaults < ActiveRecord::Migration[8.1]
  def change
    create_table :payout_scheme_defaults do |t|
      t.references :payout_scheme, null: false, foreign_key: true
      t.references :production, null: true, foreign_key: true  # null = org-level fallback
      t.date :effective_from

      t.timestamps
    end

    # Unique constraint: only one default per production per effective_from date
    # For production-level: unique on (production_id, effective_from)
    # For org-level fallback: unique on (payout_scheme.organization_id, effective_from) - handled in model
    add_index :payout_scheme_defaults, [ :production_id, :effective_from ],
              unique: true,
              where: "production_id IS NOT NULL",
              name: "idx_payout_defaults_prod_date"
    add_index :payout_scheme_defaults, [ :payout_scheme_id, :production_id ],
              name: "idx_payout_defaults_scheme_prod"
  end
end
