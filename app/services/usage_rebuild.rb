# frozen_string_literal: true

# Rebuilds one month's billable staff (StaffActivation) and performers
# (PerformerActivation) from who CocoScout actually paid through Stripe that
# month, the rule since 2026-10-05. Before that, staff were billed for being
# notified of a shift. Removes records the rule doesn't support and adds the
# ones it does; the added ones are sent to Stripe's meter as usual. What was
# already sent to Stripe can't be taken back from here; that's a credit.
class UsageRebuild
  Change = Data.define(:organization, :kind, :added, :removed)

  def self.run!(month, post: false)
    month = month.to_date.beginning_of_month
    range = month.in_time_zone.beginning_of_day..month.end_of_month.in_time_zone.end_of_day
    paid = PayoutBatchItem.joins(:payout_batch).where(status: "paid", payee_type: "Person", paid_at: range)
                          .where.not(stripe_transfer_id: nil).where.not(payout_batches: { kind: "course" })
    contributions = PayoutContribution.where(payout_batch_item_id: paid.select(:id)).where("amount_cents > 0")
    non_performing = PayoutContribution::HELD_SOURCE_TYPES + %w[ContractPayment]
    org_of = paid.pluck(:id, "payout_batches.organization_id").to_h
    staff = contributions.where(category: "staffing").pluck(:payout_batch_item_id, :payee_id)
    performers = contributions.where(category: "performer").where("source_type IS NULL OR source_type NOT IN (?)", non_performing)
                              .pluck(:payout_batch_item_id, :payee_id)
    should = { StaffActivation => staff, PerformerActivation => performers }.transform_values do |pairs|
      pairs.group_by { |item_id, _| org_of[item_id] }.transform_values { |rows| rows.map(&:last).uniq }
    end

    changes = []
    ActiveRecord::Base.transaction do
      should.each do |model, by_org|
        org_ids = (model.for_month(month).distinct.pluck(:organization_id) + by_org.keys).uniq
        Organization.where(id: org_ids).find_each do |organization|
          have = model.where(organization: organization).for_month(month).pluck(:person_id)
          want = by_org.fetch(organization.id, [])
          added = want - have
          removed = have - want
          next if added.empty? && removed.empty?

          changes << Change.new(organization: organization, kind: model == StaffActivation ? "staff" : "performers",
                                added: Person.where(id: added).order(:name).pluck(:name), removed: Person.where(id: removed).order(:name).pluck(:name))
          next unless post

          model.where(organization: organization, person_id: removed).for_month(month).delete_all
          added.each { |person_id| model.record!(organization: organization, person: Person.find(person_id), month: month) }
        end
      end
    end
    changes
  end
end
