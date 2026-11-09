# frozen_string_literal: true

require "rails_helper"

# A production's own page (Tim, 2026-11-08: "a production view page... a nice
# little dashboard without editing"): what's next, what needs doing, its
# coming dates with Home's chips, a box for each part of it and the way in,
# each drawn only when it applies to the production and to who's reading
# (ProductionPage). The Productions list opens it; Settings is one of its
# ways out.
RSpec.describe "A production's page", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, email_address: "owner@sg.example", password: password) }
  let(:org) { create(:organization, :pro, name: "Stars & Garters", owner: owner) }
  let(:production) { create(:production, organization: org, name: "A Secret Third Thing") }

  before { create(:organization_role, :manager, user: owner, organization: org) }

  def sign_in(user)
    post handle_signin_path, params: { email_address: user.email_address, password: password }
    post set_organization_path(id: org.id)
  end

  def page_for(production)
    get manage_production_path(production)
    expect(response).to have_http_status(:ok)
    Nokogiri::HTML(response.body)
  end

  def text_of(node) = node.text.squish

  describe "a first-party production, for the organization's managers" do
    let!(:show) { create(:show, production: production, date_and_time: 6.days.from_now.change(hour: 20)) }
    let!(:rehearsal) { create(:show, production: production, event_type: "rehearsal", date_and_time: 3.days.from_now.change(hour: 18)) }
    let!(:host) { create(:role, production: production, name: "Host") }

    before { sign_in(owner) }

    it "opens from the Productions list, and Settings is a button on it" do
      get manage_productions_path
      row = Nokogiri::HTML(response.body).at_css(%(a[href="#{manage_production_path(production)}"]))
      expect(row).to be_present
      expect(text_of(row)).to include("A Secret Third Thing")

      doc = page_for(production)
      expect(doc.at_css("[data-production-page]")["data-production-page"]).to eq("in_house")
      header = doc.at_css("[data-production-header]")
      expect(text_of(header.at_css("[data-production-kind]"))).to eq("First-party production · 2 dates coming")
      expect(text_of(header)).to include("No production team assigned")
      actions = header.at_css("[data-production-header-actions]")
      expect(actions.css("a").map { |a| [ text_of(a), a["href"] ] })
        .to eq([ [ "Messages", production_manage_messages_path(production) ], [ "Settings", edit_manage_production_path(production) ] ])
      expect(response.body).not_to include("Public page", "View public page")
    end

    it "says what's next and lists the coming dates, an event that isn't a show named for what it is" do
      doc = page_for(production)
      bar = doc.at_css("[data-production-next]")
      expect(bar["data-production-next"]).to eq(rehearsal.id.to_s)
      expect(text_of(bar)).to include("Next", rehearsal.date_and_time.strftime("%a, %b %-d"), "6:00 PM", "Rehearsal")
      expect(bar.at_css(%(a[href="#{manage_show_path(production, rehearsal)}"]))).to be_present
      expect(text_of(bar)).not_to include("Work the door")

      box = doc.at_css("[data-production-coming-up]")
      rows = box.css("[data-production-date]")
      expect(rows.map { |r| r["data-production-date"] }).to eq([ rehearsal.id.to_s, show.id.to_s ])
      expect(rows.map { |r| r["href"] }).to eq([ manage_show_path(production, rehearsal), manage_show_path(production, show) ])
      expect(text_of(rows.first)).to include("6:00 PM · Rehearsal")
      expect(text_of(rows.last)).to include("8:00 PM")
      expect(text_of(rows.last)).not_to include("Show ·")
      # Home's chips: the show has a role nobody's in.
      expect(rows.last.at_css('[data-chip="cast"]')["data-tone"]).to eq("warn")
      expect(text_of(box)).to include("Add a date", "All shows and events")
      expect(box.at_css(%(a[href="#{manage_shows_wizard_path(production)}"]))).to be_present
    end

    it "lists what needs doing, a line each with its way in, and nothing when nothing does" do
      expect(page_for(production).at_css("[data-production-needs-doing]")).to be_nil

      vacancy = create(:role_vacancy, show: show, role: host)
      Rails.cache.clear
      line = page_for(production).at_css('[data-production-needs-doing] [data-needs="vacancy"]')
      expect(text_of(line)).to include("#{show.date_and_time.strftime('%a, %b %-d')} needs a Host", "Fill the role")
      expect(line.at_css("a")["href"]).to eq(manage_casting_vacancy_path(production, vacancy))
    end

    it "shows the talent pool, the roles and the money, and every way in under Go to" do
      pool = production.effective_talent_pool || create(:talent_pool, production: production)
      2.times { |i| TalentPoolMembership.create!(talent_pool: pool, member: create(:person, name: "Performer #{i}")) }

      # No money yet: no box of zeros, only the way in under Go to.
      expect(page_for(production).at_css("[data-production-money]")).to be_nil
      allow_any_instance_of(FinancialSummaryService).to receive(:summary_for_period).with(:all_time)
        .and_return(FinancialSummaryService.empty_summary.merge(shows_with_data: 2, gross_revenue: 1_240.0, cost_of_shows: 600.0, gross_profit: 640.0))

      doc = page_for(production)
      cast = doc.at_css("[data-production-cast]")
      expect(text_of(cast.at_css("[data-production-pool]"))).to eq("2 in the talent pool · 1 role")
      expect(cast.css("[data-faces] > *").size).to eq(2)
      expect(cast.at_css(%(a[href="#{manage_casting_production_path(production)}"]))).to be_present

      money = doc.at_css("[data-production-money]")
      expect(text_of(money)).to include("Taken in $1,240", "Paid out $600", "What's left $640", "from 2 shows", "This production's money")

      go_to = doc.at_css("[data-production-go-to]")
      expect(go_to.css("a").map { |a| a["href"] }).to eq([
        manage_production_shows_path(production), manage_casting_production_path(production), manage_casting_availability_path(production),
        manage_signups_production_path(production), manage_money_production_financials_path(production),
        production_manage_messages_path(production), manage_production_documents_path(production), edit_manage_production_path(production)
      ])
      expect(doc.at_css("[data-production-images]")).to be_present
      expect(doc.at_css("[data-production-contract], [data-production-runs]")).to be_nil
    end

    it "shows how it's selling once it sells on CocoScout, with its link and its dates" do
      expect(text_of(page_for(production).at_css("[data-production-tickets]"))).to include("Where people get tickets isn't set.")

      patch manage_production_tickets_path(production), params: { tickets: {
        mode: "cocoscout", fee_mode: "buyer", schedule_mode: "immediate", tiers: { "0" => { name: "General", price: "20", seats: "40" } }
      } }
      doc = page_for(production)
      box = doc.at_css("[data-production-tickets]")
      expect(text_of(box.at_css("[data-production-tickets-state]"))).to eq("Selling")
      expect(text_of(box)).to include("0 sold across 1 upcoming date · $0 taken in", "/t/#{ShortLink.canonical_for!(production).code}", "Orders for this production")
      expect(box.css("[data-production-ticket-date] a").map { |a| a["href"] }).to eq([ manage_ticket_listing_path(show.reload.ticket_listing) ])
      expect(box.at_css(%(a[href="#{manage_production_ticketing_path(production)}"]))).to be_present
      expect(doc.at_css(%([data-production-date="#{show.id}"] [data-chip="tickets"]))).to be_present
      expect(doc.at_css("[data-production-go-to]").css("a").map { |a| a["href"] }).to include(manage_production_ticketing_path(production))
    end

    it "turns the next-date bar pink with Work the door while the door is open" do
      tonight = create(:show, production: production, date_and_time: 20.minutes.from_now)
      patch manage_production_tickets_path(production), params: { tickets: {
        mode: "cocoscout", fee_mode: "buyer", schedule_mode: "immediate", tiers: { "0" => { name: "General", price: "20", seats: "40" } }
      } }
      listing = tonight.reload.ticket_listing
      expect(DoorTonight.door_open?(listing)).to be(true)

      bar = page_for(production).at_css("[data-production-next]")
      expect(bar["data-production-next"]).to eq(tonight.id.to_s)
      expect(bar["class"]).to include("bg-pink-50")
      expect(text_of(bar)).to include("Door open", "0 of 40 sold", "0 checked in")
      expect(bar.css("a").map { |a| [ text_of(a), a["href"] ] })
        .to eq([ [ "Open the show", manage_show_path(production, tonight) ], [ "Work the door", door_path(listing) ] ])
    end
  end

  describe "a production with nothing coming" do
    before { sign_in(owner) }

    it "says so plainly, offers a date, names the last one, and warns about nothing" do
      create(:show, production: production, date_and_time: 3.weeks.ago.change(hour: 20))

      doc = page_for(production)
      expect(text_of(doc.at_css("[data-production-kind]"))).to eq("First-party production · no upcoming dates")
      expect(doc.at_css("[data-production-next]")).to be_nil
      expect(doc.at_css("[data-production-needs-doing]")).to be_nil
      box = doc.at_css("[data-production-coming-up]")
      expect(text_of(box)).to include("No upcoming dates.", "Add a date")
      expect(text_of(box.at_css("[data-production-last-date]"))).to include("Last date: #{3.weeks.ago.strftime('%a, %b %-d, %Y')} · 1 date in all")
      expect(text_of(doc.at_css("[data-production-pool]"))).to eq("Nobody in the talent pool · 0 roles")
      expect(doc.at_css("[data-production-signups], [data-production-people]")).to be_nil
    end
  end

  describe "for a production team member" do
    let(:viewer) { create(:user, email_address: "priya@sg.example", password: password) }
    let!(:viewer_person) { create(:person, user: viewer, name: "Priya Shah").tap { |p| viewer.update!(default_person: p) } }
    let!(:show) { create(:show, production: production, date_and_time: 6.days.from_now.change(hour: 20)) }

    before do
      create(:organization_role, user: viewer, organization: org, company_role: "member")
      ProductionPermission.create!(user: viewer, production: production, role: "viewer")
      create(:team_invitation, organization: org, production: production, email: "kim@example.com")
      sign_in(viewer)
    end

    it "leaves out Settings, the money and everything else that's the organization's managers'" do
      doc = page_for(production)
      header = doc.at_css("[data-production-header]")
      expect(text_of(header.at_css("[data-production-kind]"))).to eq("1 date coming")
      expect(text_of(header)).to include("Production team · you're a production team viewer")
      expect(text_of(header)).not_to include("invitation")
      expect(header.at_css("[data-production-header-actions]").css("a").map { |a| text_of(a) }).to eq([ "Messages" ])

      expect(doc.at_css("[data-production-money], [data-production-contract], [data-production-tickets], [data-production-images], [data-production-agreement]")).to be_nil
      expect(text_of(doc.at_css("[data-production-coming-up]"))).not_to include("Add a date")
      expect(doc.css("[data-production-go-to] a").map { |a| a["href"] }).to eq([
        manage_production_shows_path(production), manage_casting_production_path(production), manage_casting_availability_path(production),
        manage_signups_production_path(production), production_manage_messages_path(production), manage_production_documents_path(production)
      ])
      people = doc.at_css("[data-production-people]")
      expect(text_of(people)).to include("Priya Shah (you)", "Production team viewer")
      expect(text_of(people)).not_to include("kim@example.com", "Change")
      expect(response.body).not_to include(edit_manage_production_path(production))
    end
  end

  describe "a contract production" do
    let(:production) { create(:production, organization: org, production_type: "third_party", name: "Nuns4Fun") }
    let!(:contract) { create(:contract, :active, organization: org, production: production, contractor_name: "Habit Theater", production_name: "Nuns4Fun") }
    let!(:show) { create(:show, production: production, date_and_time: 5.days.from_now.change(hour: 20)) }

    before { sign_in(owner) }

    it "leads with the contract and leaves out casting, auditions and adding dates" do
      doc = page_for(production)
      expect(text_of(doc.at_css("[data-production-kind]"))).to eq("Contract production · with Habit Theater · 1 date coming")
      box = doc.at_css("[data-production-contract]")
      expect(text_of(box.at_css("[data-production-contract-state]"))).to eq("Active")
      expect(text_of(box)).to include("Habit Theater", "Made us", "Cost us", "Net to us", "Its name and description are set by the contract")
      expect(box.css("a").map { |a| a["href"] }).to include(manage_contract_path(contract), amend_basics_manage_contract_path(contract))

      expect(doc.at_css("[data-production-cast], [data-production-signups], [data-production-money], [data-production-runs]")).to be_nil
      expect(text_of(doc.at_css("[data-production-coming-up]"))).not_to include("Add a date")
      hrefs = doc.css("[data-production-go-to] a").map { |a| a["href"] }
      expect(hrefs).to include(manage_contract_path(contract), manage_money_production_incoming_path(production))
      expect(hrefs).not_to include(manage_casting_production_path(production))
    end
  end

  describe "a course" do
    let(:production) { create(:production, organization: org, production_type: "course", name: "Improv 101") }
    let!(:run) { create(:course_offering, production: production, title: "Fall run", capacity: 12) }
    let!(:session) { create(:show, production: production, event_type: "class", course_offering_id: run.id, date_and_time: 2.days.from_now.change(hour: 19)) }

    before { sign_in(owner) }

    it "shows its runs, its next session with attendance, and its registration link" do
      # Nobody's paid yet: no box of zeros.
      expect(page_for(production).at_css("[data-production-course-money]")).to be_nil
      allow_any_instance_of(CourseOffering).to receive(:financials_summary)
        .and_return({ confirmed_count: 11, refunded_count: 0, gross_cents: 264_000, owed_cents: 250_000, fee_cents: 14_000, payout_cents: 132_000, net_cents: 118_000 })

      doc = page_for(production)
      expect(text_of(doc.at_css("[data-production-kind]"))).to eq("Course · 1 run · 1 date coming")
      row = doc.at_css(%([data-production-runs] [data-production-run="#{run.id}"]))
      expect(row["href"]).to eq(manage_course_offering_path(run))
      expect(text_of(row)).to include("Fall run", "Taking registrations", "$50", "0 of 12 registered")

      bar = doc.at_css("[data-production-next]")
      expect(text_of(bar)).to include("Class 1 of 1", "0 students")
      expect(bar.css("a").map { |a| [ text_of(a), a["href"] ] })
        .to eq([ [ "Open the show", manage_show_path(production, session) ], [ "Take attendance", manage_course_offering_attendance_path(run) ] ])
      expect(text_of(doc.at_css("[data-production-registration-link]"))).to include("/c/#{run.short_code}")
      expect(text_of(doc.at_css("[data-production-course-money]"))).to include("Registrations $2,640", "11 paid", "Instructor's share $1,320", "What's left $1,180")
      expect(doc.at_css("[data-production-cast], [data-production-tickets], [data-production-money], [data-production-signups]")).to be_nil
      expect(doc.css("[data-production-go-to] a").map { |a| a["href"] }).to include(manage_course_offering_path(run))
    end
  end
end
