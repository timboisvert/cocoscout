# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Superadmin org subscription controls", type: :request do
  let(:password) { "Password123!" }
  let(:superadmin) { create(:user, email_address: "boisvert@gmail.com", password: password) }
  let(:organization) { create(:organization) }

  def sign_in(user)
    post handle_signin_path, params: { email_address: user.email_address, password: password }
  end

  context "as a superadmin" do
    before { sign_in(superadmin) }

    it "comps Pro for a number of months" do
      patch organization_subscription_path(organization),
            params: { subscription_action: "comp_months", months: 3 }

      organization.reload
      expect(organization.comped_until).to be_within(1.day).of(3.months.from_now)
      expect(organization.on_paid_plan?).to be true
    end

    it "comps Pro indefinitely" do
      patch organization_subscription_path(organization),
            params: { subscription_action: "comp_indefinite" }

      expect(organization.reload.comped_indefinitely?).to be true
    end

    it "removes a comp" do
      organization.update!(comped_indefinitely: true)

      patch organization_subscription_path(organization),
            params: { subscription_action: "remove_comp" }

      organization.reload
      expect(organization.comped_indefinitely?).to be false
      expect(organization.on_paid_plan?).to be false
    end
  end

  context "as a non-superadmin" do
    it "blocks the subscription update" do
      sign_in(create(:user, password: password))

      patch organization_subscription_path(organization),
            params: { subscription_action: "comp_indefinite" }

      expect(organization.reload.comped_indefinitely?).to be false
    end
  end
end
