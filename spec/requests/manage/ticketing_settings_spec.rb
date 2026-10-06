# frozen_string_literal: true

require "rails_helper"

# Ticketing is a Pro module, open only to superadmins while it's experimental.
# Its settings hold the box office (address, fee switch, pilot switch) and the
# v1 tax setup: one name and percentage for every ticket.
RSpec.describe "Manage ticketing settings", type: :request do
  let(:password) { "Password123!" }
  let(:superadmin) { create(:user, email_address: "boisvert@gmail.com", password: password) }
  let(:org) { create(:organization, :pro, name: "Stars & Garters", owner: superadmin) }

  def sign_in(user)
    create(:organization_role, :manager, user: user, organization: org)
    post handle_signin_path, params: { email_address: user.email_address, password: password }
    get manage_path
  end

  describe "who gets in" do
    # The box office lives at /tickets/<name>; /t/ is only the short codes.
    it "shows the box office's address under /tickets, and its short link" do
      sign_in(superadmin)
      get manage_ticketing_settings_path
      expect(response.body).to include("cocoscout.com/tickets/</span>", "The link you share is the short one", "cocoscout.com/t/#{ShortLink.canonical_for!(TicketingProfile.for(org)).code}")
      expect(response.body).not_to include("cocoscout.com/t/</span>")
    end

    it "opens for a superadmin on a Pro org, and says ticketing is off until switched on" do
      sign_in(superadmin)
      get manage_ticketing_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Ticketing is off for Stars &amp; Garters")
      expect(response.body).to include("/t/#{ShortLink.canonical_for!(TicketingProfile.for(org)).code}")
    end

    it "keeps managers who aren't superadmins out while it's experimental" do
      manager = create(:user, password: password)
      sign_in(manager)
      get manage_ticketing_path
      expect(response).to redirect_to(manage_path)
    end

    it "shows the upgrade page on a free org, superadmins included" do
      org.update!(comped_indefinitely: false)
      sign_in(superadmin)
      get manage_ticketing_settings_path
      expect(response).to have_http_status(:payment_required)
    end

    it "puts Ticketing in the Pro nav only for superadmins" do
      sign_in(superadmin)
      get manage_path
      expect(response.body).to include(manage_ticketing_path)
    end
  end

  describe "box office" do
    before { sign_in(superadmin) }

    it "saves the address, the fee switch and the pilot switch" do
      patch manage_ticketing_settings_path, params: { ticketing_profile: {
        slug: "starsandgarters", default_fee_mode: "org", default_max_per_order: 8,
        support_email: "Box@StarsAndGarters.com", enabled: "1"
      } }
      expect(response).to redirect_to(manage_ticketing_settings_section_path(section: "box_office"))
      profile = org.reload.ticketing_profile
      expect(profile.attributes.slice("slug", "default_fee_mode", "default_max_per_order", "support_email", "enabled"))
        .to eq("slug" => "starsandgarters", "default_fee_mode" => "org", "default_max_per_order" => 8,
               "support_email" => "box@starsandgarters.com", "enabled" => true)
    end

    it "sets how many days ahead buyers get their reminder, or turns it off" do
      get manage_ticketing_settings_section_path(section: "box_office")
      expect(response.body).to include("Reminder email", "1 day before the show", "30 days before the show")

      patch manage_ticketing_settings_path, params: { ticketing_profile: { reminder_days_before: "3" } }
      expect(org.reload.ticketing_profile.reminder_days_before).to eq(3)
      patch manage_ticketing_settings_path, params: { ticketing_profile: { reminder_days_before: "" } }
      expect(org.reload.ticketing_profile.reminder_days_before).to be_nil
      patch manage_ticketing_settings_path, params: { ticketing_profile: { reminder_days_before: "45" } }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "explains the fee switch with a real $20 ticket, and turns refunds after the show on with a toggle" do
      get manage_ticketing_settings_section_path(section: "box_office")
      expect(response.body).to include("$21.42").and include("$18.62")
      # Saved settings are toggles, never plain checkboxes (Tim, 2026-10-06).
      expect(response.body).to match(/<input class="sr-only peer"[^>]*name="ticketing_profile\[refunds_after_show\]"/)
    end

    it "keeps an old address working and reserved after the theater changes it" do
      profile = TicketingProfile.for(org)
      profile.update!(enabled: true)
      patch manage_ticketing_settings_path, params: { ticketing_profile: { slug: "starsandgarters" } }
      expect(profile.reload.attributes.slice("slug", "previous_slugs")).to eq("slug" => "starsandgarters", "previous_slugs" => [ "stars-garters" ])

      get "/tickets/stars-garters"
      expect(response).to redirect_to("/tickets/starsandgarters")
      expect(response).to have_http_status(:moved_permanently)

      other = create(:organization, name: "Stars and Garters Too")
      taken = TicketingProfile.new(organization: other, slug: "stars-garters")
      expect(taken).not_to be_valid
      expect(taken.errors[:slug]).to include("is another box office's old address")
      expect(TicketingProfile.for(create(:organization, name: "Stars & Garters")).slug).to eq("stars-garters-2")
    end

    it "refuses an address the /t pages already use" do
      patch manage_ticketing_settings_path, params: { ticketing_profile: { slug: "orders" } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(org.reload.ticketing_profile.slug).to eq("stars-garters")
    end
  end

  describe "tax" do
    before { sign_in(superadmin) }

    def save_tax(percent, name: "Sales tax", mode: "added")
      patch manage_ticketing_settings_tax_path, params: { tax: { name: name, percent: percent, mode: mode } }
    end

    it "sets one percentage for every ticket, and shows what it does to a $20 ticket" do
      save_tax("10.25")
      rule = org.tax_rules.sole
      expect([ rule.money_kind, rule.scope_type, rule.mode, rule.tax_rates.sole.rate_bps ]).to eq([ "tickets", nil, "added", 1_025 ])

      get manage_ticketing_settings_section_path(section: "tax")
      expect(response.body).to include('value="10.25"').and include("$2.05")
    end

    it "takes the tax off when the percentage is cleared" do
      save_tax("10.25")
      save_tax("")
      expect(org.tax_rules).to be_empty
      expect(flash[:notice]).to eq("Tickets now carry no tax.")
    end

    it "retires a rate sales have used instead of changing it" do
      save_tax("10.25")
      old_rate = org.tax_rates.sole
      listing = create(:ticket_listing, organization: org)
      ticket = create(:ticket, ticket_order: create(:ticket_order, ticket_listing: listing))
      TaxLine.create!(organization: org, taxable: ticket, tax_rate: old_rate, name: "Sales tax", rate_bps: 1_025,
                      base_cents: 2_000, tax_cents: 205, sale_date: Date.current)

      save_tax("9", mode: "included")
      expect(old_rate.reload.archived_at).to be_present
      rule = org.tax_rules.sole
      expect([ rule.mode, rule.tax_rates.sole.rate_bps ]).to eq([ "included", 900 ])
    end

    it "explains a number that isn't a percentage" do
      save_tax("ten")
      expect(flash[:alert]).to eq("Enter the tax as a percentage, like 10.25")
      expect(org.tax_rules).to be_empty
    end
  end
  describe "notifications" do
    before { sign_in(superadmin) }

    it "shows who gets what, and saves the theater's choices with extra addresses" do
      get manage_ticketing_settings_section_path(section: "notifications")
      expect(response.body).to include("Who hears about what", "Each sale", "Daily summary", "Disputed charge", "Other email addresses")

      patch manage_ticketing_settings_notifications_path,
            params: { updating: "1", emails: "box@starsandgarters.com", rules: { "sale" => [ "email:box@starsandgarters.com" ] } }
      expect(response).to redirect_to(manage_ticketing_settings_section_path(section: "notifications"))
      expect(TicketingNotifications.new(org).emails_for("sale")).to eq([ "box@starsandgarters.com" ])
      expect(TicketingNotifications.new(org).emails_for("daily_summary")).to be_empty

      patch manage_ticketing_settings_notifications_path, params: { updating: "1", emails: "nope" }
      expect(flash[:alert]).to eq("nope isn't an email address.")
    end
  end
end
