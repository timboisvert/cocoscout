# frozen_string_literal: true

# There is no organization-level payout calculation any more: a production
# chooses its own. So that nothing that pays today stops paying, every
# org-level default (production_id NULL) — and every legacy is_default flag —
# becomes a per-production row for each of that org's productions that has
# no calculation of its own. Then the org-level rows go.
class RetireOrgLevelPayoutDefaults < ActiveRecord::Migration[8.1]
  class MigrationPayoutScheme < ApplicationRecord
    self.table_name = "payout_schemes"
  end

  class MigrationPayoutSchemeDefault < ApplicationRecord
    self.table_name = "payout_scheme_defaults"
  end

  class MigrationProduction < ApplicationRecord
    self.table_name = "productions"
  end

  def up
    covered = MigrationPayoutSchemeDefault.where.not(production_id: nil).distinct.pluck(:production_id).to_set

    # Org-level join rows first (the current mechanism), then the legacy flag.
    org_rows = MigrationPayoutSchemeDefault.where(production_id: nil).order(Arel.sql("effective_from NULLS FIRST")).to_a
    org_rows.each do |row|
      scheme = MigrationPayoutScheme.find_by(id: row.payout_scheme_id)
      next unless scheme&.organization_id

      MigrationProduction.where(organization_id: scheme.organization_id).find_each do |production|
        next if covered.include?(production.id)

        MigrationPayoutSchemeDefault.create!(payout_scheme_id: scheme.id, production_id: production.id, effective_from: nil)
        covered << production.id
      end
    end

    MigrationPayoutScheme.where(is_default: true).find_each do |scheme|
      if scheme.production_id.present?
        next if covered.include?(scheme.production_id)

        MigrationPayoutSchemeDefault.create!(payout_scheme_id: scheme.id, production_id: scheme.production_id, effective_from: nil)
        covered << scheme.production_id
      elsif scheme.organization_id.present?
        MigrationProduction.where(organization_id: scheme.organization_id).find_each do |production|
          next if covered.include?(production.id)

          MigrationPayoutSchemeDefault.create!(payout_scheme_id: scheme.id, production_id: production.id, effective_from: nil)
          covered << production.id
        end
      end
    end

    MigrationPayoutSchemeDefault.where(production_id: nil).delete_all
    MigrationPayoutScheme.where(is_default: true).update_all(is_default: false)

    change_column_null :payout_scheme_defaults, :production_id, false
  end

  def down
    change_column_null :payout_scheme_defaults, :production_id, true
  end
end
