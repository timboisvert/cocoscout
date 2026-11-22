# frozen_string_literal: true

# For someone's My pages (Tim, 2026-11-22): each organization paying them
# personally this year, with what it has paid them and where their W-9 there
# stands, each leading to their page about the year (My::TaxFormsController
# #year). Across every profile on their account.
class MyTaxYears
  Row = Data.define(:organization, :paid_cents, :w9, :request, :year)

  # organizations: limit to these (My Contracts passes its contracts'
  # organizations); otherwise every organization that has paid them.
  def self.for(user, organizations: nil, exclude_ids: [])
    people_ids = user.people.active.pluck(:id)
    return [] if people_ids.empty?

    year = Time.current.year
    orgs = organizations || paying_organizations(people_ids)
    Array(orgs).uniq.reject { |org| exclude_ids.include?(org.id) }.filter_map do |org|
      earnings = Tax::YearEarnings.for(org, year)
      paid = people_ids.sum { |id| earnings[id]&.net_cents.to_i }
      w9 = org.w9_submissions.current.where(person_id: people_ids).order(signed_at: :desc).first
      request = W9Request.where(organization: org, person_id: people_ids).order(:requested_at).first
      next if paid <= 0 && w9.nil? && request.nil?

      Row.new(organization: org, paid_cents: paid, w9: w9, request: request, year: year)
    end.sort_by { |row| -row.paid_cents }
  end

  def self.paying_organizations(people_ids)
    ids = PayoutLedgerEntry.where(payee_type: "Person", payee_id: people_ids, entry_type: "payout").distinct.pluck(:organization_id) |
          Contractor.where(person_id: people_ids).distinct.pluck(:organization_id) |
          W9Request.where(person_id: people_ids).distinct.pluck(:organization_id)
    Organization.where(id: ids).to_a
  end
end
