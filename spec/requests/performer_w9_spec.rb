# frozen_string_literal: true

require "rails_helper"

# W-9s and 1099s for everyone an organization pays personally, not only its
# staff (Tim, 2026-11-22): a daily check requests a W-9 by email and
# notification at $1,500 paid in the year, reminds weekly until it's in, the
# person's page shows their year against the 1099 line, the Taxes page shows
# where each person stands, and their 1099 is generated with the staff's.
RSpec.describe "W-9s for performers and contract people", type: :request do
  include ActiveJob::TestHelper

  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let(:org) { create(:organization, :pro, name: "Stars & Garters", owner: owner) }
  let(:performer) { create(:user, password: password) }
  let!(:person) { create(:person, user: performer, name: "Thea Fox", email: performer.email_address).tap { |p| performer.update!(default_person: p) } }
  let(:year) { Time.current.year }

  before do
    create(:organization_role, :manager, user: owner, organization: org)
    PerformerTaxTemplates.ensure!
  end

  def sign_in(user)
    get signout_path
    post handle_signin_path, params: { email_address: user.email_address, password: password }
  end

  def pay!(cents, at: Time.current.beginning_of_year + 2.months)
    batch = create(:payout_batch, organization: org, kind: "staff_pay", status: "completed", payday: at.to_date)
    item = PayoutBatchItem.create!(payout_batch: batch, payee: person, amount_cents: cents, status: "pending")
    PayoutContribution.create!(payout_batch: batch, payout_batch_item: item, payee: person, category: "performer",
                               amount_cents: cents, label: "Show pay")
    item.update!(status: "paid", paid_at: at)
    PayoutLedgerEntry.post!(organization: org, payee: person, entry_type: "payout", amount_cents: -cents,
                            source: item, occurred_at: at, category: "performer")
  end

  it "requests a W-9 at $1,500 by email and notification, then reminds weekly until it's in" do
    pay!(1_400_00)
    expect { PerformerW9SweepJob.perform_now }.not_to(change(W9Request, :count))

    pay!(200_00)
    expect { PerformerW9SweepJob.perform_now }.to change(W9Request, :count).by(1)
      .and have_enqueued_mail(StaffTaxFormMailer, :performer_w9_request)
    request = W9Request.find_by!(organization: org, person: person)
    expect(performer.notifications.last.title).to include("Stars & Garters needs a W-9 from you")

    # Nothing again the next day; a reminder a week on.
    expect { PerformerW9SweepJob.perform_now(now: 1.day.from_now) }.not_to have_enqueued_mail(StaffTaxFormMailer, :performer_w9_request)
    expect { PerformerW9SweepJob.perform_now(now: 8.days.from_now) }.to have_enqueued_mail(StaffTaxFormMailer, :performer_w9_request)
    expect(request.reload.last_reminded_at).to be_present
  end

  it "shows them their year, takes their W-9, and stops the reminders" do
    pay!(1_640_00)
    PerformerW9SweepJob.perform_now
    sign_in(performer)

    get my_tax_year_path(org.id)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("$1,640", "W-9 requested", "1099 line", "$2,000", "Fill in your W-9",
                                     "https://www.irs.gov/forms-pubs/about-form-w-9", "What a 1099-NEC is")

    get my_w9_path(org.id)
    expect(response).to have_http_status(:ok)
    post my_w9_path(org.id), params: {
      certify: "1",
      w9: { legal_name: "Thea Fox", tax_classification: "individual", address_line1: "1 Main St", city: "Chicago",
            state: "IL", zip: "60601", tin_type: "ssn", tin: "123456789", signature_name: "Thea Fox" }
    }
    expect(response).to redirect_to(my_tax_year_path(org.id))
    expect(org.w9_submissions.current.find_by(person: person)).to be_present
    expect { PerformerW9SweepJob.perform_now(now: 8.days.from_now) }.not_to have_enqueued_mail(StaffTaxFormMailer, :performer_w9_request)
  end

  it "turns away someone the organization has never paid" do
    sign_in(performer)
    get my_tax_year_path(org.id)
    expect(response).to redirect_to(my_dashboard_path)
  end

  it "shows the manager who's been paid and requested, and generates their 1099 with the staff's" do
    pay!(2_100_00)
    PerformerW9SweepJob.perform_now
    sign_in(owner)

    get manage_staffing_taxes_path
    expect(response.body).to include("Performers and contract people", "Thea Fox", "$2,100", "Requested #{Time.current.strftime('%b %-d')}")

    org.create_tax_setting!(legal_name: "Stars & Garters LLC", ein: "123456789", address_line1: "1 State St",
                            city: "Chicago", state: "IL", zip: "60601")
    forms = TaxForm1099.generate_for_year!(organization: org, tax_year: year)
    expect(forms.map(&:person_id)).to eq([ person.id ])
    expect(forms.first.nec_box1_cents).to eq(2_100_00)
  end
end
