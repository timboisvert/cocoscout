# frozen_string_literal: true

# The data step of RetireOrgLevelPayoutDefaults, kept out of the migration so
# it can be exercised by a spec.
#
# There is no organization-level payout calculation any more: a production
# chooses its own. So that nothing that pays today stops paying — and pays
# with the same calculation on the same dates — every org-level default row
# (production_id NULL) and every legacy is_default flag is mirrored onto each
# of that org's productions that has no calculation of its own: one
# production row per org row, same effective_from, so default_for_show
# resolves per date exactly as it did through the org fallback. Productions
# that already have a row of their own are left untouched. Then the org-level
# rows go and the flags are cleared.
#
# Talks to the tables through its own bare models so it doesn't depend on
# whatever validations or associations the app's models carry later.
class PayoutDefaultMigration
  class Scheme < ApplicationRecord
    self.table_name = "payout_schemes"
  end

  class Default < ApplicationRecord
    self.table_name = "payout_scheme_defaults"
  end

  class Prod < ApplicationRecord
    self.table_name = "productions"
  end

  def self.run!
    new.run!
  end

  def run!
    Default.transaction do
      covered = Default.where.not(production_id: nil).distinct.pluck(:production_id).to_set

      # Legacy production-level is_default flags become the production's own row.
      Scheme.where(is_default: true).where.not(production_id: nil).find_each do |scheme|
        next if covered.include?(scheme.production_id)

        Default.create!(payout_scheme_id: scheme.id, production_id: scheme.production_id, effective_from: nil)
        covered << scheme.production_id
      end

      mirrors_by_org.each do |organization_id, mirrors|
        Prod.where(organization_id: organization_id).where.not(id: covered.to_a).find_each do |production|
          mirrors.each do |mirror|
            Default.create!(payout_scheme_id: mirror[:payout_scheme_id], production_id: production.id,
                            effective_from: mirror[:effective_from])
          end
          covered << production.id
        end
      end

      Default.where(production_id: nil).delete_all
      Scheme.where(is_default: true).update_all(is_default: false)
    end
  end

  private

  # { organization_id => [ { payout_scheme_id:, effective_from: }, ... ] } —
  # what each org's fallback looked like, date by date. Org-level join rows
  # first (the current mechanism), then the legacy flag as an undated row; one
  # row per start date, first wins.
  def mirrors_by_org
    by_org = Hash.new { |hash, key| hash[key] = [] }

    Default.where(production_id: nil).order(:id).each do |row|
      scheme = Scheme.find_by(id: row.payout_scheme_id)
      next unless scheme&.organization_id

      add_mirror(by_org[scheme.organization_id], scheme.id, row.effective_from)
    end

    Scheme.where(is_default: true, production_id: nil).where.not(organization_id: nil).order(:id).each do |scheme|
      add_mirror(by_org[scheme.organization_id], scheme.id, nil)
    end

    by_org
  end

  def add_mirror(mirrors, payout_scheme_id, effective_from)
    return if mirrors.any? { |mirror| mirror[:effective_from] == effective_from }

    mirrors << { payout_scheme_id: payout_scheme_id, effective_from: effective_from }
  end
end
