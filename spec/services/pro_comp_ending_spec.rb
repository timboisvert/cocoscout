# frozen_string_literal: true

require "rails_helper"

# When an organization's complimentary Pro is ending (Tim, 2026-11-01): it
# hears what Pro did for it and what staying costs, can keep Pro in a click,
# and its last month's usage still bills if it doesn't.
RSpec.describe "Complimentary Pro ending", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password, email_address: "owner@sg.example") }
  let!(:owner_person) { create(:person, user: owner, name: "Tim Owner") }
  let(:org) do
    create(:organization, name: "Stars & Garters", owner: owner, stripe_customer_id: "cus_sg", comped_indefinitely: false,
                          comped_until: Time.zone.local(2026, 12, 31).end_of_day)
  end
  let(:now) { Time.zone.local(2026, 12, 17, 10) }

  before do
    create(:organization_role, :manager, user: owner, organization: org)
    PlatformTemplates.ensure!(keys: %w[pro_comp_ending])
  end

  it "tells them what Pro did for them, what it costs, and what they'd lose" do
    travel_to now do
      create(:show, production: create(:production, organization: org), date_and_time: now - 5.days)
      ending = ProCompEnding.new(org)
      expect([ ending.ending_soon?, ending.days_left, ending.due_reminders ]).to eq([ true, 14, [ "two_weeks" ] ])
      expect(ending.value_lines).to include("Ran 1 show and events")
      expect(ending.price_line).to include("$29 a month on your one monthly bill", "$299 a year", "saving $49")
    end
  end

  it "emails the billing contacts two weeks and three days before, once each" do
    travel_to now do
      expect { ProCompEndingJob.perform_now }.to change { ActionMailer::Base.deliveries.size }.by(1)
      mail = ActionMailer::Base.deliveries.last
      expect(mail.to).to eq([ "owner@sg.example" ])
      expect(mail.subject).to eq("Your complimentary CocoScout Pro ends December 31")
      html = mail.html_part&.body&.decoded || mail.body.decoded
      expect(html).to include("Hi Tim", "14 days from now", "Keep Pro", "$29 a month", "free Producer plan", "Ticketing")
      expect { ProCompEndingJob.perform_now }.not_to(change { ActionMailer::Base.deliveries.size })
    end
    travel_to Time.zone.local(2026, 12, 28, 10) do
      expect { ProCompEndingJob.perform_now }.to change { ActionMailer::Base.deliveries.size }.by(1)
      expect(org.reload.comp_reminders).to eq("2026-12-31" => %w[two_weeks three_days])
    end
  end

  it "shows the warning on the Billing tab, and Keep Pro carries on on the monthly bill from the day the comp ends" do
    travel_to now do
      post handle_signin_path, params: { email_address: owner.email_address, password: password }
      get manage_path
      get section_manage_organization_path(org, section: "billing")
      expect(response.body).to include("Your complimentary Pro ends December 31", "14 days left", "Keep Pro, $29/month", "Keep Pro, $299/year",
                                       "On the free Producer plan you", "Nothing is charged unless you choose it")

      allow(Stripe::Customer).to receive(:retrieve).with("cus_sg")
                                                   .and_return(Stripe::Customer.construct_from(id: "cus_sg", invoice_settings: { default_payment_method: "pm_bank" }))
      allow(StaffMeterService).to receive(:ensure_staffing_subscription!)
      post manage_billing_keep_pro_path(interval: "month")
      expect(flash[:notice]).to include("You're keeping Pro. From January 1 it's $29 a month")
      expect(org.reload.pro_on_monthly_bill?(Time.zone.local(2027, 1, 2))).to be(true)
      # The comp's days are never charged; January is.
      expect([ UsageRules.pro_cents(org, Date.new(2026, 12, 1)), UsageRules.pro_cents(org, Date.new(2027, 1, 1)) ]).to eq([ 0, 2_900 ])
      expect(ProCompEnding.new(org).ending_soon?).to be(false)
      get section_manage_organization_path(org, section: "billing")
      expect(response.body).not_to include("Your complimentary Pro ends")
    end
  end

  it "starts a yearly plan's first year when the comp ends" do
    travel_to now do
      post handle_signin_path, params: { email_address: owner.email_address, password: password }
      get manage_path
      allow(SubscriptionPlan).to receive(:price_id).and_return("price_year")
      expect(Stripe::Checkout::Session).to receive(:create)
        .with(hash_including(mode: "subscription", subscription_data: hash_including(trial_end: org.comped_until.to_i)))
        .and_return(double(url: "https://checkout.stripe.com/year"))
      post manage_billing_keep_pro_path(interval: "year")
      expect(response).to redirect_to("https://checkout.stripe.com/year")
    end
  end

  it "still bills December's usage on the January 1 bill after the comp ends" do
    org.update!(staffing_subscription_id: "sub_usage")
    expect(org.bills_usage_in?(Date.new(2026, 12, 1))).to be(true)
    travel_to Time.zone.local(2027, 1, 1, 1) do
      expect(org.bills_usage?).to be(false)
      expect(org.bills_usage_in?(Date.new(2027, 1, 1))).to be(false)
    end
  end
end
