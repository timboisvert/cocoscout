# frozen_string_literal: true

require "rails_helper"

RSpec.describe "My::TaxForms 1099 recipient copy", type: :request do
  let(:password) { "Password123!" }
  let(:user) { create(:user, password: password) }
  let!(:person) { create(:person, user: user, name: "Sam Staffer").tap { |p| user.update!(default_person: p) } }
  let!(:org) { create(:organization, :pro) }
  let!(:member) { create(:organization_staff_member, organization: org, person: person, acknowledged_at: 1.week.ago) }

  before { post handle_signin_path, params: { email_address: user.email_address, password: password } }

  it "opens the recipient's copy of a delivered 1099" do
    create(:tax_form_1099, organization: org, person: person, status: "delivered",
           delivered_at: 1.day.ago, tax_year: 2026)
    get my_form_1099_path(org.id, 2026)
    expect(response.media_type).to eq("application/pdf")
  end

  it "hides drafts from the recipient" do
    create(:tax_form_1099, organization: org, person: person, status: "draft", tax_year: 2026)
    get my_form_1099_path(org.id, 2026)
    expect(response).to redirect_to(my_payments_path)
  end

  it "lists delivered 1099s on My Payments" do
    create(:tax_form_1099, organization: org, person: person, status: "delivered",
           delivered_at: 1.day.ago, tax_year: 2026)
    get my_payments_path
    expect(response.body).to include("Tax documents").and include("2026 1099-NEC")
  end
end
