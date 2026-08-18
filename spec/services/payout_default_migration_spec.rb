# frozen_string_literal: true

require "rails_helper"

# The data step of RetireOrgLevelPayoutDefaults: org-level default rows become
# per-production rows, date for date, so a show resolves to the same
# calculation on the same date as it did through the org fallback.
RSpec.describe PayoutDefaultMigration do
  let(:org) { create(:organization, :pro) }
  let(:rules) { { "allocation" => [], "distribution" => { "method" => "flat_fee", "flat_amount" => 50.0 }, "performer_overrides" => {} } }
  let!(:old_calc) { PayoutScheme.create!(organization: org, name: "Old", rules: rules) }
  let!(:new_calc) { PayoutScheme.create!(organization: org, name: "New", rules: rules) }
  let!(:own_calc) { PayoutScheme.create!(organization: org, name: "Own", rules: rules) }
  let!(:friday) { create(:production, organization: org, name: "Friday") }
  let!(:saturday) { create(:production, organization: org, name: "Saturday") }
  let!(:sunday) { create(:production, organization: org, name: "Sunday") }

  # The migration ran against the test schema already, so production_id is
  # NOT NULL there; loosen it inside this example's transaction to stage the
  # pre-migration data (DDL rolls back with the transaction in Postgres).
  before { ActiveRecord::Base.connection.change_column_null(:payout_scheme_defaults, :production_id, true) }
  after { PayoutSchemeDefault.reset_column_information }

  def org_row!(scheme, effective_from)
    PayoutSchemeDefault.insert!({ payout_scheme_id: scheme.id, production_id: nil, effective_from: effective_from,
                                  created_at: Time.current, updated_at: Time.current })
  end

  def rows_for(production)
    PayoutSchemeDefault.for_production(production).order(Arel.sql("effective_from NULLS FIRST")).map { |r| [ r.payout_scheme, r.effective_from ] }
  end

  it "mirrors every org-level row onto each production without one of its own, same dates, and drops the org rows" do
    org_row!(old_calc, nil)
    org_row!(new_calc, Date.new(2025, 6, 1))
    own_calc.add_default_for_production!(sunday, effective_from: Date.new(2024, 3, 1))

    described_class.run!

    expect(rows_for(friday)).to eq([ [ old_calc, nil ], [ new_calc, Date.new(2025, 6, 1) ] ])
    expect(rows_for(saturday)).to eq([ [ old_calc, nil ], [ new_calc, Date.new(2025, 6, 1) ] ])
    expect(rows_for(sunday)).to eq([ [ own_calc, Date.new(2024, 3, 1) ] ])
    expect(PayoutSchemeDefault.where(production_id: nil)).not_to exist

    # Resolution per date is what it was through the org fallback.
    early = create(:show, production: friday, date_and_time: Time.zone.local(2025, 1, 10, 20))
    late = create(:show, production: friday, date_and_time: Time.zone.local(2025, 9, 10, 20))
    expect(PayoutScheme.default_for_show(early)).to eq(old_calc)
    expect(PayoutScheme.default_for_show(late)).to eq(new_calc)
  end

  it "turns a legacy is_default flag into rows too — an org flag mirrored undated, a production flag as that production's own" do
    old_calc.update_column(:is_default, true)
    prod_calc = PayoutScheme.create!(production: saturday, name: "Sat only", rules: rules)
    prod_calc.update_column(:is_default, true)

    described_class.run!

    expect(rows_for(friday)).to eq([ [ old_calc, nil ] ])
    expect(rows_for(saturday)).to eq([ [ prod_calc, nil ] ])
    expect(PayoutScheme.where(is_default: true)).not_to exist
  end

  it "prefers the org-level row over the legacy flag when both are undated" do
    org_row!(new_calc, nil)
    old_calc.update_column(:is_default, true)

    described_class.run!

    expect(rows_for(friday)).to eq([ [ new_calc, nil ] ])
  end

  it "does nothing to an org with no org-level rows" do
    own_calc.add_default_for_production!(sunday)

    described_class.run!

    expect(rows_for(friday)).to be_empty
    expect(rows_for(sunday)).to eq([ [ own_calc, nil ] ])
  end
end
