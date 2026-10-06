# frozen_string_literal: true

# Brings one month's billable staff (StaffActivation) and performers
# (PerformerActivation) in line with UsageRules: adds everyone whose paid
# work that month has happened, and (when rebuilding) removes anyone the
# rules don't support. The hourly sweep (UsageSweepJob) only adds; a rebuild
# also removes, for a month counted under an old rule. Added people are sent
# to Stripe's meter as usual. What Stripe already counted can't be taken
# back from here; the bill is corrected when Stripe drafts it
# (UsageInvoiceCorrection).
class UsageRebuild
  Change = Data.define(:organization, :kind, :added, :removed)

  def self.run!(month, post: false, remove: true, now: Time.current)
    month = month.to_date.beginning_of_month
    should = { StaffActivation => UsageRules.staff(month, now: now), PerformerActivation => UsageRules.performers(month, now: now) }
    changes = []
    ActiveRecord::Base.transaction do
      should.each do |model, by_org|
        org_ids = ((remove ? model.for_month(month).distinct.pluck(:organization_id) : []) + by_org.keys).uniq
        Organization.where(id: org_ids).find_each do |organization|
          want = by_org.fetch(organization.id, {})
          have = model.where(organization: organization).for_month(month).pluck(:person_id)
          added = want.keys - have
          removed = remove ? have - want.keys : []
          next if added.empty? && removed.empty?

          changes << Change.new(organization: organization, kind: model == StaffActivation ? "staff" : "performers",
                                added: Person.where(id: added).order(:name).pluck(:name), removed: Person.where(id: removed).order(:name).pluck(:name))
          next unless post

          model.where(organization: organization, person_id: removed).for_month(month).delete_all if removed.any?
          added.each { |person_id| model.record!(organization: organization, person: Person.find(person_id), month: month, at: want[person_id]) }
        end
      end
    end
    changes
  end
end
