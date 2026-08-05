# frozen_string_literal: true

require "rails_helper"

# Every "something needs your attention" box on My pages renders through
# shared/_alert_panel: label, one big line, one small line, one button on the
# right. These specs render the real pages and check each converted alert still
# says what it needs to say — and that nobody has re-implemented the panel.
RSpec.describe "My alert panels", type: :request do
  let(:password) { "Password123!" }
  let(:user) { create(:user, password: password) }
  let!(:person) { create(:person, user: user, phone: "5551234567").tap { |p| user.update!(default_person: p) } }
  let(:organization) { create(:organization, :pro) }
  let(:production) { create(:production, organization: organization) }

  before { post handle_signin_path, params: { email_address: user.email_address, password: password } }

  def panels_in(body)
    body.scan("data-alert-panel").size
  end

  describe "You're owed" do
    before do
      PayoutLedgerEntry.create!(organization: organization, payee: person, entry_type: "earning",
                                category: "performer", amount_cents: 12_500, occurred_at: Time.current)
    end

    it "leads with the amount and sends an unbanked person to connect their bank" do
      get my_dashboard_path

      expect(response.body).to include("You&#39;re owed")
      expect(response.body).to include("$125.00")
      expect(response.body).to include("Connect your bank &amp; get paid")
    end

    it "sends a payable person to My Payments rather than a 'see what it's for' link" do
      person.update!(stripe_account_id: "acct_test", payouts_enabled: true)

      get my_dashboard_path

      expect(response.body).to include("Go to My Payments")
      expect(response.body).not_to include("See what it's for")
    end
  end

  describe "Waiting on you" do
    it "counts the open tasks and links to My Tasks" do
      pool = create(:talent_pool, production: production)
      TalentPoolMembership.create!(talent_pool: pool, member: person)
      create(:show, production: production, date_and_time: 1.week.from_now)

      get my_dashboard_path

      expect(response.body).to include("Waiting on you")
      expect(response.body).to include("1 task waiting")
      expect(response.body).to include(my_tasks_path)
    end
  end

  describe "You're invited to fill a role" do
    let(:show) { create(:show, production: production, date_and_time: 1.week.from_now) }
    let(:role) { create(:role, production: production, name: "Host") }
    let(:vacancy) { create(:role_vacancy, show: show, role: role) }
    let!(:invitation) { create(:role_vacancy_invitation, role_vacancy: vacancy, person: person) }

    it "offers claim and decline on both My Calendar and My Shows" do
      [ my_dashboard_path, my_shows_path ].each do |path|
        get path

        expect(response.body).to include("You&#39;re invited to fill a role"), "missing on #{path}"
        expect(response.body).to include("Host")
        expect(response.body).to include(claim_vacancy_path(invitation.token))
        expect(response.body).to include(decline_claim_vacancy_path(invitation.token))
      end
    end
  end

  describe "Complete your info" do
    it "raises one alert per missing detail" do
      pool = create(:talent_pool, production: production)
      TalentPoolMembership.create!(talent_pool: pool, member: person)
      person.update!(phone: nil) # contact + headshot + payment all missing

      get my_dashboard_path

      expect(response.body).to include("Complete your info")
      expect(response.body).to include("Add a phone number")
      expect(response.body).to include("Helps producers recognize you in casting and at the door.")
      expect(response.body).to include("Connect your bank so productions can pay you directly.")
    end
  end

  describe "the shape itself" do
    it "renders one panel per thing needing attention" do
      PayoutLedgerEntry.create!(organization: organization, payee: person, entry_type: "earning",
                                category: "performer", amount_cents: 5_000, occurred_at: Time.current)
      create(:organization_staff_member, organization: organization, person: person, onboarding_state: "invited")

      get my_dashboard_path

      # You're owed + Finish setting up. (No talent pool, so no profile gaps.)
      expect(panels_in(response.body)).to eq(2)
      expect(response.body).to include("Finish setting up")
    end

    it "is the only implementation of the panel — nobody hand-rolls a second one" do
      offenders = Dir[Rails.root.join("app/views/**/*.erb")].reject { |f| f.end_with?("shared/_alert_panel.html.erb") }
                                                            .select { |f| File.read(f).include?("border-2 border-pink-200 bg-gradient-to-r from-pink-50") }
      expect(offenders.map { |f| f.sub("#{Rails.root}/", "") }).to be_empty
    end
  end
end
