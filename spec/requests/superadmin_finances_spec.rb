# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Superadmin Finances - Org Payouts", type: :request do
  let(:superadmin_user) { create(:user, email_address: "boisvert@gmail.com", password: "Password123!") }
  let(:regular_user) { create(:user, password: "Password123!") }

  let(:organization) { create(:organization) }
  let(:production) { create(:production, organization: organization) }
  let(:course_offering) { create(:course_offering, production: production) }

  def sign_in_as_superadmin
    post handle_signin_path, params: { email_address: superadmin_user.email_address, password: "Password123!" }
  end

  def sign_in_as_regular
    post handle_signin_path, params: { email_address: regular_user.email_address, password: "Password123!" }
  end

  describe "GET /superadmin/finances (enhanced with org obligations)" do
    before { sign_in_as_superadmin }

    it "shows org obligations section" do
      create(:course_registration, course_offering: course_offering, amount_cents: 10000, status: "confirmed")
      get finances_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Organization Obligations")
      expect(response.body).to include(organization.name)
    end

    it "redirects non-superadmins" do
      sign_in_as_regular
      get finances_path
      expect(response).to redirect_to(my_dashboard_path)
    end
  end

  describe "GET /superadmin/finances/orgs/:org_id" do
    before { sign_in_as_superadmin }

    it "shows org detail page with course breakdown" do
      create(:course_registration, course_offering: course_offering, amount_cents: 10000, status: "confirmed")
      get finances_org_detail_path(org_id: organization.id)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(organization.name)
      expect(response.body).to include("Course Breakdown")
    end

    it "shows payment history" do
      create(:org_payout, organization: organization, course_offering: course_offering, amount_cents: 5000)
      get finances_org_detail_path(org_id: organization.id)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Payment History")
    end
  end

  describe "GET /superadmin/finances/courses/:course_offering_id" do
    before { sign_in_as_superadmin }

    it "shows course detail page with revenue summary" do
      create(:course_registration, course_offering: course_offering, amount_cents: 10000, status: "confirmed")
      get finances_course_detail_path(course_offering_id: course_offering.id)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(course_offering.title)
      expect(response.body).to include("Revenue Summary")
      expect(response.body).to include("Record Payment")
    end

    it "shows fully paid message when balance is zero" do
      create(:course_registration, course_offering: course_offering, amount_cents: 10000, status: "confirmed")
      owed = OrgPayout.owed_cents_for_course(course_offering)
      create(:org_payout, organization: organization, course_offering: course_offering, amount_cents: owed)
      get finances_course_detail_path(course_offering_id: course_offering.id)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Fully Paid")
    end
  end

  describe "POST /superadmin/finances/courses/:course_offering_id/pay" do
    before { sign_in_as_superadmin }

    it "creates a full_course payment" do
      create(:course_registration, course_offering: course_offering, amount_cents: 10000, status: "confirmed")

      expect {
        post finances_record_payment_path(course_offering_id: course_offering.id), params: {
          payout_type: "full_course",
          payment_method: "zelle",
          notes: "Full course payment"
        }
      }.to change(OrgPayout, :count).by(1)

      payout = OrgPayout.last
      expect(payout.amount_cents).to eq(9500) # 95% of 10000
      expect(payout.payout_type).to eq("full_course")
      expect(payout.payment_method).to eq("zelle")
      expect(payout.status).to eq("paid")
      expect(response).to redirect_to(finances_course_detail_path(course_offering_id: course_offering.id))
    end

    it "creates a custom payment" do
      expect {
        post finances_record_payment_path(course_offering_id: course_offering.id), params: {
          payout_type: "custom",
          amount: "50.00",
          payment_method: "venmo",
          notes: "Partial"
        }
      }.to change(OrgPayout, :count).by(1)

      expect(OrgPayout.last.amount_cents).to eq(5000)
    end

    it "creates a per_session payment" do
      location = create(:location)
      show1 = create(:show, production: production, location: location, date_and_time: 1.day.from_now)
      show2 = create(:show, production: production, location: location, date_and_time: 2.days.from_now)
      create(:course_registration, course_offering: course_offering, amount_cents: 10000, status: "confirmed")

      expect {
        post finances_record_payment_path(course_offering_id: course_offering.id), params: {
          payout_type: "per_session",
          session_ids: [ show1.id ],
          payment_method: "cash"
        }
      }.to change(OrgPayout, :count).by(1)

      payout = OrgPayout.last
      expect(payout.payout_type).to eq("per_session")
      expect(payout.covers_sessions).to eq([ show1.id ])
      # 9500 owed total / 2 sessions * 1 session = 4750
      expect(payout.amount_cents).to eq(4750)
    end
  end

  describe "DELETE /superadmin/finances/payments/:id" do
    before { sign_in_as_superadmin }

    it "deletes a payment and redirects to course detail" do
      payout = create(:org_payout, organization: organization, course_offering: course_offering)

      expect {
        delete finances_delete_payment_path(id: payout.id)
      }.to change(OrgPayout, :count).by(-1)

      expect(response).to redirect_to(finances_course_detail_path(course_offering_id: course_offering.id))
    end

    it "redirects to org detail if no course_offering" do
      payout = create(:org_payout, organization: organization, course_offering: nil)

      delete finances_delete_payment_path(id: payout.id)
      expect(response).to redirect_to(finances_org_detail_path(org_id: organization.id))
    end
  end

  describe "POST /superadmin/finances/payments/:id/mark_paid" do
    before { sign_in_as_superadmin }

    it "marks a pending payment as paid" do
      payout = create(:org_payout, :pending, organization: organization, course_offering: course_offering)

      post finances_mark_payment_paid_path(id: payout.id)
      payout.reload
      expect(payout.status).to eq("paid")
      expect(payout.paid_at).to be_present
      expect(payout.paid_by_user).to eq(superadmin_user)
    end
  end
end
