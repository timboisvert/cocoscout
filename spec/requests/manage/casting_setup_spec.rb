# frozen_string_literal: true

require "rails_helper"

# Casting set-up (Tim, 2026-11-18). Each production is marked "We cast
# people in this production" or "We don't cast people in this production";
# a production people are cast in that has never been set up shows a "Not
# set up" panel that opens a step-by-step set-up; and the casting board, the
# production's page, and a date's page each say where casting stands.
RSpec.describe "Casting set-up", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, email_address: "owner@sg.example", password: password) }
  let(:org) { create(:organization, :pro, name: "The Holly Problem Co", owner: owner) }
  let(:production) { create(:production, organization: org, name: "The Holly Problem") }

  # Wizard state rides in Rails.cache; the test env cache is a null store.
  let(:memory_cache) { ActiveSupport::Cache::MemoryStore.new }

  before do
    allow(Rails).to receive(:cache).and_return(memory_cache)
    create(:organization_role, :manager, user: owner, organization: org)
    create(:person, user: owner).tap { |person| owner.update!(default_person: person) }
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
    post set_organization_path(id: org.id)
  end

  def doc = Nokogiri::HTML(response.body)
  def text_of(node) = node.text.squish

  def board
    get manage_casting_production_path(production)
    expect(response).to have_http_status(:ok)
    doc
  end

  describe "the casting board's status" do
    it "shows the Not set up panel, with the way in, for a production that has never been set up" do
      panel = board.at_css("[data-casting-status='not_set_up']")

      expect(text_of(panel)).to include("Not set up", "Set up casting for The Holly Problem")
      link = panel.at_css("a[href='#{manage_casting_setup_path(production)}']")
      expect(text_of(link)).to eq("Set it up")
    end

    it "says Casting on with its counts once it's set up" do
      create(:role, production: production, name: "Host")
      create(:role, production: production, name: "Performer", quantity: 4)
      create(:show, production: production, date_and_time: 1.week.from_now)
      create(:show, production: production, event_type: "rehearsal", date_and_time: 2.days.from_now)

      line = board.at_css("[data-casting-status='on']")
      expect(text_of(line)).to eq("Casting on 2 roles · Nobody in the talent pool yet · Casting is on for 1 of the 2 dates coming up")
    end

    it "says Off, with the way to change it, when people aren't cast in the production" do
      production.update!(casts_people: false)

      line = board.at_css("[data-casting-status='off']")
      expect(text_of(line)).to include("Off", "We don't cast people in The Holly Problem.")
      expect(line.at_css("a[href='#{manage_casting_settings_path(production)}']")).to be_present
    end
  end

  describe "the casting board's list" do
    it "never says nothing is scheduled when dates exist with casting off" do
      create(:show, production: production, event_type: "rehearsal", date_and_time: 2.days.from_now)
      create(:show, production: production, event_type: "rehearsal", date_and_time: 3.days.from_now)

      note = board.at_css("[data-casting-list-note]")
      expect(response.body).not_to include("No upcoming shows scheduled.")
      expect(text_of(note)).to include("Casting is off for all 2 dates coming up, so there is nothing to cast here.")
      expect(note.at_css("a")["href"]).to eq(manage_casting_settings_path(production, anchor: "dates"))
    end

    it "says how many more dates have casting off under the ones it lists, and says so plainly when there are none at all" do
      expect(text_of(board.at_css("[data-casting-list-note]"))).to eq("No dates are coming up in The Holly Problem.")

      create(:show, production: production, date_and_time: 1.week.from_now)
      create(:show, production: production, event_type: "rehearsal", date_and_time: 2.days.from_now)
      expect(text_of(board.at_css("[data-casting-list-note]"))).to include("Casting is off for 1 more date coming up.")
    end
  end

  describe "set-up, step by step" do
    let(:venue) { create(:organization, :pro, name: "Stars & Garters") }
    let(:venue_production) { create(:production, organization: venue, production_type: "third_party", name: "The Holly Problem") }
    let!(:show) { create(:show, production: production, date_and_time: 2.weeks.from_now.change(hour: 20)) }
    let!(:rehearsal) { create(:show, production: production, event_type: "rehearsal", date_and_time: 1.week.from_now.change(hour: 18)) }
    let!(:booked) do
      theirs = create(:show, production: venue_production, date_and_time: 3.weeks.from_now.change(hour: 20))
      create(:show, production: production, linked_show: theirs, following_contract: true, date_and_time: theirs.date_and_time)
    end

    it "walks who you cast, roles or acts, your roles, the dates, and a review, and changes nothing until Finish" do
      get manage_casting_setup_path(production)
      expect(response).to have_http_status(:ok)
      expect(text_of(doc.at_css("[data-casting-setup-step='who'] h2"))).to eq("Who do you cast in The Holly Problem?")
      expect(response.body).not_to include("We don't cast people in this production")

      post manage_casting_setup_save_who_path(production), params: { casting_source: "manual" }
      expect(response).to redirect_to(manage_casting_setup_style_path(production))
      follow_redirect!
      expect(doc.at_css("[data-casting-setup-step='style']")).to be_present

      post manage_casting_setup_save_style_path(production), params: { casting_mode: "role_based" }
      expect(response).to redirect_to(manage_casting_setup_roles_path(production))
      follow_redirect!
      expect(doc.at_css("[data-casting-setup-step='roles'] #roles-list")).to be_present
      # A role is its name and how many: no Performing / Technical choice.
      expect(doc.at_css("#roles-list select")).to be_nil
      expect(response.body).not_to include("Crew / Technical", "Technical")

      post manage_casting_setup_save_roles_path(production),
           params: { has_roles: "yes", roles: { "0" => { name: "Host", quantity: "1" },
                                                 "1" => { name: "Performer", quantity: "4", category: "technical" },
                                                 "2" => { name: "", quantity: "1" } } }
      expect(response).to redirect_to(manage_casting_setup_dates_path(production))
      follow_redirect!

      # The choice Ticketing offers for which dates it sells: all
      # performances (where it starts), by event type, or specific dates.
      which = doc.at_css("[data-casting-which-dates]")
      expect(which.css("input[name=matching]").map { |radio| [ radio["value"], radio["checked"].present? ] })
        .to eq([ [ "all", true ], [ "event_types", false ], [ "manual", false ] ])
      expect(text_of(which)).to include("All performances", "By event type", "Specific dates")
      expect(which.css("input[name='event_types[]']").select { |box| box["checked"] }.map { |box| box["value"] }).to eq(%w[show class workshop open_mic])
      # Under Specific dates, every coming date with its kind: the ones
      # with casting on today ticked, and the one from a contract says who
      # it's booked with.
      rows = which.css("[data-casting-date]")
      expect(rows.map { |row| row["data-casting-date"].to_i }).to eq([ rehearsal.id, show.id, booked.id ])
      expect(rows.map { |row| row.at_css("input[type=checkbox]")["checked"].present? }).to eq([ false, true, true ])
      expect(text_of(rows[0])).to include("Rehearsal")
      expect(text_of(rows[2])).to include("Show", "Booked at Stars & Garters")
      expect(which.css("input[type=checkbox]").map { |box| box["class"] }).to all(include("accent-pink-500"))

      post manage_casting_setup_save_dates_path(production), params: { matching: "manual", show_ids: [ show.id, rehearsal.id ] }
      expect(response).to redirect_to(manage_casting_setup_review_path(production))
      follow_redirect!
      review = text_of(doc.at_css("[data-casting-setup-review]"))
      expect(review).to include("Anyone, added by name or email as you need them.", "Roles: named positions to fill.", "Host and Performer ×4",
                                "Specific dates: only the ones you picked.", "2 of the 3 dates coming up are cast.",
                                "A new date starts with casting off until you pick it.")

      expect(production.reload).to have_attributes(casting_source: "talent_pool", casting_setup_completed: false, casting_event_matching: "all")
      expect(production.roles).to be_empty
      expect(rehearsal.reload.casting_enabled).to be(false)

      post manage_casting_setup_finish_path(production)
      expect(response).to redirect_to(manage_casting_production_path(production))

      expect(production.reload).to have_attributes(casting_source: "manual", casting_mode: "role_based", casting_setup_completed: true, casting_state: :on,
                                                   casting_event_matching: "manual")
      # Whatever a stale page posts, a role made here is a plain role.
      expect(production.roles.order(:position).pluck(:name, :quantity, :category)).to eq([ [ "Host", 1, "performing" ], [ "Performer", 4, "performing" ] ])
      expect(show.reload.casting_enabled).to be(true)
      expect(rehearsal.reload.casting_enabled).to be(true)
      expect(booked.reload.casting_enabled).to be(false)

      follow_redirect!
      expect(doc.at_css("[data-casting-status='on']")).to be_present
    end

    it "casts only the kinds of event ticked, when that is the choice" do
      post manage_casting_setup_save_who_path(production), params: { casting_source: "talent_pool" }
      post manage_casting_setup_save_style_path(production), params: { casting_mode: "role_based" }
      post manage_casting_setup_save_roles_path(production), params: { has_roles: "no" }
      post manage_casting_setup_save_dates_path(production), params: { matching: "event_types", event_types: %w[show rehearsal] }
      follow_redirect!
      expect(text_of(doc.at_css("[data-casting-setup-review]"))).to include("By event type: shows and rehearsals.", "All 3 dates coming up are cast.")

      post manage_casting_setup_finish_path(production)
      expect(production.reload).to have_attributes(casting_event_matching: "event_types", casting_event_type_filter: %w[show rehearsal])
      expect(production.shows.pluck(:casting_enabled)).to all(be(true))
      expect(production.shows.create!(event_type: "rehearsal", date_and_time: 6.weeks.from_now, is_online: true).casting_enabled).to be(true)
      expect(production.shows.create!(event_type: "class", date_and_time: 6.weeks.from_now, is_online: true).casting_enabled).to be(false)
    end

    it "builds a lineup when the production casts by acts" do
      post manage_casting_setup_save_who_path(production), params: { casting_source: "talent_pool" }
      post manage_casting_setup_save_style_path(production), params: { casting_mode: "act_based" }
      follow_redirect!
      expect(text_of(doc.at_css("[data-casting-setup-step='roles'] h2"))).to eq("Build your lineup")

      post manage_casting_setup_save_roles_path(production),
           params: { has_roles: "yes", roles: { "0" => { name: "Magic", category: "performing" }, "1" => { name: "Intermission", category: "break" },
                                                 "2" => { name: "MC", quantity: "1", category: "show_role" } } }
      post manage_casting_setup_save_dates_path(production), params: { show_ids: [ show.id ] }
      post manage_casting_setup_finish_path(production)

      expect(production.reload).to be_act_based
      expect(production.roles.order(:position).pluck(:name, :category, :standing)).to eq([ [ "Magic", "performing", false ], [ "Intermission", "break", false ], [ "MC", "performing", true ] ])
    end

    it "leaves the production as it was when set-up is canceled" do
      post manage_casting_setup_save_who_path(production), params: { casting_source: "manual" }
      delete manage_casting_setup_cancel_path(production)

      expect(response).to redirect_to(manage_casting_production_path(production))
      expect(production.reload).to have_attributes(casting_source: "talent_pool", casting_setup_completed: false)
    end

    it "sends a production that's already set up, or one people aren't cast in, to Casting Settings" do
      create(:role, production: production)
      get manage_casting_setup_path(production)
      expect(response).to redirect_to(manage_casting_settings_path(production))
      expect(flash[:notice]).to include("already set up")

      production.update!(casts_people: false)
      get manage_casting_setup_path(production)
      expect(response).to redirect_to(manage_casting_settings_path(production))
      expect(flash[:notice]).to include("We don't cast people in The Holly Problem.")
    end

    it "is for the production's managers" do
      viewer = create(:user, password: password)
      create(:person, user: viewer).tap { |person| viewer.update!(default_person: person) }
      create(:organization_role, user: viewer, organization: org, company_role: "viewer")
      get signout_path
      post handle_signin_path, params: { email_address: viewer.email_address, password: password }
      post set_organization_path(id: org.id)

      get manage_casting_setup_path(production)
      expect(response).to redirect_to(manage_path)
    end
  end

  describe "Casting Settings" do
    let!(:show) { create(:show, production: production, date_and_time: 2.weeks.from_now) }
    let!(:rehearsal) { create(:show, production: production, event_type: "rehearsal", date_and_time: 1.week.from_now) }

    it "opens with the production's answer, in Tim's words" do
      get manage_casting_settings_path(production)

      card = doc.at_css("[data-casting-answer]")
      expect(card["data-casting-answer"]).to eq("yes")
      expect(text_of(card)).to include("We cast people in this production", "We don't cast people in this production")
      expect(response.body).not_to include("Do you cast")
      expect(card.at_css("input[name=casts_people][value=yes]")["checked"]).to be_present
    end

    it "saves the answer and brings the coming dates into line with it" do
      patch manage_casting_answer_path(production), params: { casts_people: "no" }
      expect(response).to redirect_to(manage_casting_settings_path(production))
      expect(production.reload.casts_people).to be(false)
      expect(show.reload.casting_enabled).to be(false)

      patch manage_casting_answer_path(production), params: { casts_people: "yes" }
      expect(production.reload.casts_people).to be(true)
      expect(show.reload.casting_enabled).to be(true)
      expect(rehearsal.reload.casting_enabled).to be(false)
    end

    # Tim, 2026-11-18: the tabs read as a mess. Three tabs now (Casting,
    # Roles, Talent Pool), each a stack of cards like Ticketing's and Money's,
    # with the dates in a window opened from the first.
    it "has three tabs, with no line of prose above them" do
      get manage_casting_settings_path(production)

      tabs = doc.css("nav[aria-label='Settings sections'] a").map { |a| text_of(a) }
      expect(tabs).to eq([ "Casting", "Roles", "Talent Pool" ])
      expect(response.body).not_to include("casts by roles", "casts by acts")
      expect(doc.css("[data-settings-card]").map { |card| card["data-settings-card"] }).to eq(%w[answer source dates attendance])
    end

    it "keeps the tab strip from scrolling up and down" do
      get manage_casting_settings_path(production)

      strip = doc.at_css("nav[aria-label='Settings sections']")
      expect(strip["class"]).to include("overflow-x-auto", "overflow-y-hidden")
      expect(strip.css("a").map { |a| a["class"] }).to all(satisfy { |classes| !classes.include?("-mb-px") })
    end

    # Tim, 2026-11-18: "all events, just events of the following type, or
    # types... or only specific dates. Like ticketing got this right."
    it "asks which dates are cast the way Ticketing asks which it sells, and saving brings the coming dates into line" do
      get manage_casting_settings_path(production)

      card = doc.at_css("#dates[data-settings-card='dates']")
      expect(text_of(card.at_css("h2"))).to eq("Which dates?")
      expect(card.css("input[name=matching]").map { |radio| [ radio["value"], radio["checked"].present? ] })
        .to eq([ [ "all", true ], [ "event_types", false ], [ "manual", false ] ])
      expect(card.css("[data-casting-date]").map { |row| [ row["data-casting-date"].to_i, row.at_css("input")["checked"].present? ] })
        .to eq([ [ rehearsal.id, false ], [ show.id, true ] ])

      patch manage_casting_dates_path(production), params: { matching: "event_types", event_types: %w[rehearsal] }
      expect(response).to redirect_to(manage_casting_settings_path(production, anchor: "dates"))
      expect(production.reload).to have_attributes(casting_event_matching: "event_types", casting_event_type_filter: %w[rehearsal])
      expect(rehearsal.reload.casting_enabled).to be(true)
      expect(show.reload.casting_enabled).to be(false)

      patch manage_casting_dates_path(production), params: { matching: "manual", show_ids: [ show.id ] }
      expect(production.reload.casting_event_matching).to eq("manual")
      expect(show.reload.casting_enabled).to be(true)
      expect(rehearsal.reload.casting_enabled).to be(false)
      get manage_casting_settings_path(production)
      expect(doc.at_css("#dates input[name=matching][value=manual]")["checked"]).to be_present

      patch manage_casting_dates_path(production), params: { matching: "all" }
      expect(production.reload.casting_event_matching).to eq("all")
      expect(show.reload.casting_enabled).to be(true)
      expect(rehearsal.reload.casting_enabled).to be(false)
    end

    it "has nothing to choose under Which dates? when people aren't cast in the production" do
      production.update!(casts_people: false)

      get manage_casting_settings_path(production)
      card = doc.at_css("[data-settings-card='dates']")
      expect(card.at_css("input[name=matching]")).to be_nil
      expect(text_of(card.at_css("[data-casting-dates-off]"))).to include("We don't cast people in The Holly Problem, so none of its dates are cast.")

      patch manage_casting_dates_path(production), params: { matching: "manual", show_ids: [ show.id ] }
      expect(production.reload.casting_event_matching).to eq("all")
    end

    it "lands an old address on the tab that holds it now, the dates one at its card" do
      get manage_casting_settings_section_path(production_id: production, section: "source")
      expect(response).to redirect_to(manage_casting_settings_path(production))

      get manage_casting_settings_section_path(production_id: production, section: "dates")
      expect(response).to redirect_to(manage_casting_settings_path(production, anchor: "dates"))
    end

    it "saves who you cast and attendance from their own cards, and roles or acts from the Roles tab" do
      patch manage_update_casting_settings_path(production), params: { production: { casting_source: "manual" } }
      expect(response).to redirect_to(manage_casting_settings_path(production))
      expect(production.reload).to be_casting_manual

      patch manage_update_casting_settings_path(production), params: { production: { default_attendance_enabled: "1" } }
      expect(production.reload.default_attendance_enabled).to be(true)

      get manage_casting_settings_section_path(production_id: production, section: "roles")
      expect(doc.css("[data-settings-card]").map { |card| card["data-settings-card"] }).to eq(%w[style roles])
      expect(text_of(doc.at_css("[data-roles-empty]"))).to include("No roles yet.")
      expect(response.body).not_to include("Next step")

      patch manage_update_casting_settings_path(production), params: { section: "roles", production: { casting_mode: "act_based" } }
      expect(response).to redirect_to(manage_casting_settings_section_path(production_id: production, section: "roles"))
      expect(production.reload).to be_act_based
    end
  end

  describe "the production's own settings" do
    it "has a Casting tab with the same answer and the way into set-up" do
      get edit_manage_production_path(production)

      tab = doc.at_css("[data-production-casting-tab]")
      expect(tab.at_css("[data-casting-answer]")).to be_present
      expect(tab.at_css("input[name=return_to]")["value"]).to eq("production_edit")
      expect(tab.at_css("a[href='#{manage_casting_setup_path(production)}']")).to be_present
      expect(doc.css("nav button[data-tabs-target=tab]").map { |b| text_of(b) }).to include("Casting")

      patch manage_casting_answer_path(production), params: { casts_people: "no", return_to: "production_edit" }
      expect(response).to redirect_to(edit_manage_production_path(production, tab: 9))
    end

    it "has no Casting tab for a production booked by a contract" do
      contracted = create(:production, organization: org, production_type: "third_party")

      get edit_manage_production_path(contracted)
      expect(doc.at_css("[data-production-casting-tab]")).to be_nil
    end
  end

  describe "the production's page" do
    def cast_card
      get manage_production_path(production)
      expect(response).to have_http_status(:ok)
      doc.at_css("[data-production-cast]")
    end

    it "says Not set up, Casting on with counts, or Off on the Cast and talent pool card" do
      create(:show, production: production, date_and_time: 1.week.from_now)
      card = cast_card
      expect(card["data-casting-state"]).to eq("not_set_up")
      expect(text_of(card.at_css("[data-production-casting-badge]"))).to eq("Not set up")
      expect(card.at_css("a[href='#{manage_casting_setup_path(production)}']")).to be_present

      create(:role, production: production)
      card = cast_card
      expect(text_of(card.at_css("[data-production-casting-badge]"))).to eq("Casting on")
      expect(text_of(card.at_css("[data-production-pool]"))).to eq("Nobody in the talent pool · 1 role · Casting is on for the one date coming up")

      production.update!(casts_people: false)
      card = cast_card
      expect(text_of(card.at_css("[data-production-casting-badge]"))).to eq("Off")
      expect(text_of(card)).to include("We don't cast people in this production.")
    end

    context "with dates booked at another organization and casting not set up" do
      let(:venue) { create(:organization, :pro, name: "Stars & Garters") }
      let(:venue_production) { create(:production, organization: venue, production_type: "third_party") }

      before do
        2.times do |i|
          theirs = create(:show, production: venue_production, date_and_time: (2 + i).weeks.from_now)
          create(:show, production: production, linked_show: theirs, following_contract: true, date_and_time: theirs.date_and_time)
        end
      end

      it "says so once under To do, with both ways to answer it" do
        get manage_production_path(production)
        line = doc.at_css("[data-needs='casting']")
        # The box is headed "To do", never "Needs doing" (Tim, 2026-11-18).
        expect(text_of(doc.at_css("[data-production-needs-doing] h2"))).to eq("To do")
        expect(response.body).not_to include("Needs doing")

        expect(text_of(line)).to include("2 dates are booked at Stars & Garters, and casting isn't set up yet.")
        expect(line.at_css("a[href='#{manage_casting_setup_path(production)}']").text.squish).to eq("Set up casting")
        expect(text_of(line)).to include("We don't cast people in it")

        patch manage_casting_answer_path(production), params: { casts_people: "no", return_to: "production" }
        expect(response).to redirect_to(manage_production_path(production))
        expect(production.reload.casts_people).to be(false)
        expect(production.shows.pluck(:casting_enabled)).to all(be(false))

        follow_redirect!
        expect(doc.at_css("[data-needs='casting']")).to be_nil
      end

      it "goes once casting is set up" do
        create(:role, production: production)

        get manage_production_path(production)
        expect(doc.at_css("[data-needs='casting']")).to be_nil
      end
    end
  end

  describe "a date's page" do
    def date_page(show)
      get manage_show_path(production, show)
      expect(response).to have_http_status(:ok)
      doc
    end

    it "gives a casting-off date one quiet line with Turn casting on, which turns it on" do
      rehearsal = create(:show, production: production, event_type: "rehearsal", date_and_time: 1.week.from_now)
      create(:role, production: production)

      note = date_page(rehearsal).at_css("[data-show-casting-note='off']")
      expect(text_of(note)).to include("Casting is off for this rehearsal, so nobody is assigned to it.", "Turn casting on")

      post manage_turn_casting_on_show_path(production, rehearsal)
      expect(response).to redirect_to(manage_show_path(production, rehearsal))
      expect(rehearsal.reload.casting_enabled).to be(true)
      expect(date_page(rehearsal).at_css("[data-show-casting-note='off']")).to be_nil
    end

    it "says why when people aren't cast in the production" do
      production.update!(casts_people: false)
      show = create(:show, production: production, date_and_time: 1.week.from_now)

      note = date_page(show).at_css("[data-show-casting-note='off']")
      expect(text_of(note)).to include("We don't cast people in The Holly Problem, so casting is off for this show, and nobody is assigned to it.")
    end

    it "offers Set up casting, or Add roles, where it used to say No roles defined yet" do
      show = create(:show, production: production, date_and_time: 1.week.from_now)

      note = date_page(show).at_css("[data-show-casting-note='no_roles']")
      expect(response.body).not_to include("No roles defined yet")
      expect(text_of(note)).to include("Casting isn't set up for The Holly Problem yet, so there is nothing to cast on this date.")
      expect(note.at_css("a[href='#{manage_casting_setup_path(production)}']").text.squish).to eq("Set up casting")

      production.update!(casting_setup_completed: true)
      note = date_page(show).at_css("[data-show-casting-note='no_roles']")
      expect(text_of(note)).to include("The Holly Problem has no roles yet, so there is nothing to cast on this date.")
      add = note.at_css("a[href='#{manage_casting_settings_section_path(production_id: production, section: 'roles')}']")
      expect(add.text.squish).to eq("Add roles")
      # The date's own casting page is still a press away.
      expect(note.at_css("a[href='#{manage_casting_show_cast_path(production, show)}']").text.squish).to eq("Manage Cast")
    end

    it "draws the Casting box as before once there are roles" do
      create(:role, production: production, name: "Host")
      show = create(:show, production: production, date_and_time: 1.week.from_now)

      page = date_page(show)
      expect(page.at_css("[data-show-casting-note]")).to be_nil
      expect(response.body).to include("Casting Progress", "0/1")
    end
  end

  describe "Home and the shows list" do
    let!(:role) { create(:role, production: production, name: "Host") }
    let!(:rehearsal) { create(:show, production: production, event_type: "rehearsal", date_and_time: 2.days.from_now.change(hour: 18)) }
    let!(:show) { create(:show, production: production, date_and_time: 2.days.from_now.change(hour: 20)) }

    it "never counts a casting-off date's roles as uncast" do
      week = HomeWeek.new(organization: org, user: owner, days: [ rehearsal.date_and_time.to_date ], shows: [ rehearsal, show ],
                          show_cast: {}, pro_manager: true)

      expect(week.row(rehearsal).cast).to be_nil
      expect(week.row(show).cast.uncast).to eq(1)
    end

    it "still shows who is on a casting-off date" do
      create(:show_person_role_assignment, show: rehearsal, role: role)
      week = HomeWeek.new(organization: org, user: owner, days: [ rehearsal.date_and_time.to_date ], shows: [ rehearsal ],
                          show_cast: {}, pro_manager: true)

      expect(week.row(rehearsal).cast).to have_attributes(uncast: 0, assigned: 1)
    end

    it "draws no role slots for a casting-off date on the production's shows list, as on the organization's" do
      get manage_production_shows_path(production, filter: "upcoming", view_mode: "all")
      expect(response).to have_http_status(:ok)
      empty_slots = doc.css("[data-tooltip-text*='(not assigned)']")
      expect(empty_slots.size).to eq(1)

      get manage_shows_path(filter: "upcoming", view_mode: "all")
      expect(doc.css("[data-tooltip-text*='(not assigned)']").size).to eq(1)
    end
  end

  # Tim, 2026-11-18: "I'd rather just the role, the number of them, that's
  # it." Crew is Staffing's now, so the Performing / Technical choice is gone
  # from every place a role is made, edited, or listed.
  describe "a role is its name and how many" do
    let!(:host) { create(:role, production: production, name: "Host", position: 1) }
    let!(:crew) { create(:role, production: production, name: "Board Op", position: 2) }
    let!(:show) { create(:show, production: production, date_and_time: 1.week.from_now) }

    it "offers no Performing / Technical choice in Casting Settings and labels no role with one" do
      get manage_casting_settings_section_path(production_id: production, section: "roles")
      expect(response).to have_http_status(:ok)

      expect(doc.at_css("select[name='role[category]']")).to be_nil
      expect(doc.at_css("[data-role-modal-target='categorySelect']")).to be_nil
      expect(doc.css("label").map { |label| text_of(label) }).not_to include("Category")
      visible = doc.css("span, h3, option").map { |node| text_of(node).downcase }
      expect(visible).not_to include("performing", "technical")
      expect(response.body).to include("Host", "Board Op")
    end

    it "lists a date's roles as one list, with no Performing or Technical headings, and no choice in the date's own roles" do
      get manage_casting_show_cast_path(production, show)
      expect(response).to have_http_status(:ok)

      expect(doc.css("h3").map { |heading| text_of(heading).downcase }).not_to include("performing", "technical")
      expect(doc.at_css("[data-show-roles-modal-target='categorySelect']")).to be_nil
      expect(doc.css("label").map { |label| text_of(label) }).not_to include("Category")
      expect(response.body).to include("Host", "Board Op")
    end

    it "makes every role a plain role, whatever a stale page posts" do
      post manage_create_casting_role_path(production), params: { role: { name: "Usher", quantity: "2", category: "technical", restricted: "0" } }
      expect(production.roles.find_by!(name: "Usher")).to have_attributes(quantity: 2, category: "performing")

      patch manage_update_casting_role_path(production, crew), params: { role: { name: "Board Operator", quantity: "1", category: "technical", restricted: "0" } }
      expect(crew.reload).to have_attributes(name: "Board Operator", category: "performing")
    end
  end

  describe "the new-production wizard" do
    it "stores 'We don't cast people in this production' on the production, and its dates start with casting off" do
      post manage_productions_wizard_save_name_path, params: { name: "Rental Night" }
      get manage_productions_wizard_casting_path
      expect(response.body).to include("We don't cast people in this production")
      expect(response.body).not_to include("No Casting Needed")

      post manage_productions_wizard_save_casting_path, params: { casting_source: "none" }
      post manage_productions_wizard_save_shows_path, params: { has_shows: "yes" }
      post manage_productions_wizard_save_schedule_path,
           params: { schedule_type: "single", details: { event_type: "show", is_online: "true" }, shows: { "0" => { date_and_time: 3.weeks.from_now.strftime("%Y-%m-%dT%H:%M") } } }
      post manage_productions_wizard_create_path

      made = org.productions.find_by!(name: "Rental Night")
      expect(made).to have_attributes(casts_people: false, casting_state: :off)
      expect(made.shows.pluck(:casting_enabled)).to eq([ false ])

      later = made.shows.create!(event_type: "show", date_and_time: 5.weeks.from_now, is_online: true)
      expect(later.casting_enabled).to be(false)
    end

    it "marks a production whose casting questions were answered as set up, and its rehearsals start with casting off" do
      post manage_productions_wizard_save_name_path, params: { name: "Improv Jam" }
      post manage_productions_wizard_save_casting_path, params: { casting_source: "talent_pool" }
      post manage_productions_wizard_save_casting_style_path, params: { casting_mode: "role_based" }
      post manage_productions_wizard_save_roles_path, params: { has_roles: "no" }
      post manage_productions_wizard_save_shows_path, params: { has_shows: "yes" }
      post manage_productions_wizard_save_schedule_path,
           params: { schedule_type: "single", details: { event_type: "rehearsal", is_online: "true" }, shows: { "0" => { date_and_time: 3.weeks.from_now.strftime("%Y-%m-%dT%H:%M") } } }
      post manage_productions_wizard_create_path

      made = org.productions.find_by!(name: "Improv Jam")
      expect(made).to have_attributes(casts_people: true, casting_state: :on)
      expect(made.shows.pluck(:casting_enabled)).to eq([ false ])
    end
  end

  describe "the add-a-date wizard" do
    it "starts a show with casting off in a production people aren't cast in, and the tick box still wins" do
      production.update!(casts_people: false)

      post manage_shows_wizard_save_event_type_path(production), params: { event_type: "show" }
      get manage_shows_wizard_details_path(production)
      expect(doc.at_css("input[type=checkbox][name=casting_enabled]")["checked"]).to be_nil
      expect(response.body).to include("It starts off because we don't cast people in The Holly Problem.")

      post manage_shows_wizard_save_details_path(production), params: { casting_enabled: "1" }
      expect(memory_cache.read("show_wizard:#{owner.id}:#{production.id}").with_indifferent_access[:casting_enabled]).to be(true)
    end
  end
end
