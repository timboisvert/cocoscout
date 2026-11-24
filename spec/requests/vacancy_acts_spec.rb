# frozen_string_literal: true

require "rails_helper"

# Can't Make It on a show cast by acts (Tim, 2026-11-24): a performer with
# more than one act in the show chooses which acts they can't make. Every act
# starts ticked, unticking one keeps it, the production team gets one notice
# that names every act, and the performer can come back for an act they kept.
# One act, or a show cast by roles, is the single choice it always was.
RSpec.describe "Can't Make It with several acts", type: :request do
  include ActiveJob::TestHelper

  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org, name: "The Velvet Hour", casting_mode: "act_based") }

  # Lineup: Fan Dance, Juggling, an intermission, Aerial Hoop, Finale: acts 1 to 4, the break unnumbered.
  let!(:lineup) do
    [ [ "Fan Dance", nil ], [ "Juggling", nil ], [ "Intermission", "break" ], [ "Aerial Hoop", nil ], [ "Finale", nil ] ].each_with_index.map do |(name, category), index|
      create(:role, { production: production, name: name, position: index }.merge(category ? { category: category } : {}))
    end
  end
  let!(:show) { create(:show, production: production, date_and_time: 3.weeks.from_now, casting_finalized_at: Time.current) }

  let(:user) { create(:user, password: password) }
  let!(:person) { create(:person, user: user, name: "Juniper Vale") }
  let(:token) { VacancyController.generate_token(person) }

  def act(name) = show.available_roles.find_by!(name: name)
  def key(role, who = person) = "#{role.id}:#{who.class.name}:#{who.id}"
  def page = Nokogiri::HTML(response.body)
  def held = show.show_person_role_assignments.where(assignable: person).map { |a| a.role.name }.sort

  before do
    [ "Fan Dance", "Aerial Hoop", "Finale" ].each { |name| create(:show_person_role_assignment, show: show, role: act(name), assignable: person) }
  end

  describe "the page" do
    it "lists every act the performer holds, each ticked, by its place in the lineup" do
      get vacancy_path(show, token: token)

      expect(response).to have_http_status(:ok)
      boxes = page.css("input[type='checkbox'][name='role_ids[]']")
      expect(boxes.size).to eq(3)
      expect(boxes.map { |box| box["checked"] }).to all(be_present)
      expect(boxes.map { |box| box["class"] }).to all(include("accent-pink-500"))
      expect(boxes.map { |box| box["value"] }).to eq([ key(act("Fan Dance")), key(act("Aerial Hoop")), key(act("Finale")) ])
      expect(page.css("input[type='radio']")).to be_empty

      rows = page.css("[data-vacancy-form-target='actRow']").map { |row| row.css("p").map { |line| line.text.squish } }
      expect(rows).to eq([ [ "Act 1 · Fan Dance", "Juniper Vale", "You're keeping this act." ],
                           [ "Act 3 · Aerial Hoop", "Juniper Vale", "You're keeping this act." ],
                           [ "Act 4 · Finale", "Juniper Vale", "You're keeping this act." ] ])
      expect(page.css("[data-kept]").map { |line| line["class"] }).to all(include("hidden"))

      text = page.text.squish
      expect(text).to include("You have 3 acts in this show.", "Which acts can't you make?",
                              "All 3 are ticked to start. Untick any act you can still make.")
      expect(page.at_css("button[data-vacancy-form-target='submit']").text.squish).to eq("I confirm that I can't make these 3 acts")
      expect(page.at_css("form[data-controller='vacancy-form']").to_h).to include("data-vacancy-form-unit-value" => "act", "data-vacancy-form-units-value" => "acts")
    end

    it "is the single choice it always was for a performer with one act" do
      show.show_person_role_assignments.where(role: [ act("Aerial Hoop"), act("Finale") ]).destroy_all

      get vacancy_path(show, token: token)

      expect(page.css("input[type='checkbox'][name='role_ids[]']")).to be_empty
      radios = page.css("input[type='radio'][name='role_ids[]']")
      expect(radios.size).to eq(1)
      expect(radios.first["checked"]).to be_present
      expect(page.text.squish).to include("Select the role you can't fulfill:", "as Act 1 · Fan Dance")
      expect(page.at_css("button[type='submit']").text.squish).to eq("I confirm that I can't make it")
    end

    it "is the single choice it always was on a show cast by roles" do
      role_production = create(:production, organization: create(:organization))
      role_show = create(:show, production: role_production, date_and_time: 3.weeks.from_now)
      %w[Aerialist Juggler].each_with_index do |name, index|
        create(:show_person_role_assignment, show: role_show, assignable: person, role: create(:role, production: role_production, name: name, position: index))
      end

      get vacancy_path(role_show, token: token)

      expect(page.css("input[type='checkbox'][name='role_ids[]']")).to be_empty
      expect(page.css("input[type='radio'][name='role_ids[]']").size).to eq(2)
      expect(page.text.squish).to include("Select the role you can't fulfill:")
    end

    it "calls them assignments when a show role is among the acts" do
      mc = show.custom_roles.create!(name: "MC", standing: true, position: 9, production: production)
      create(:show_person_role_assignment, show: show, role: mc, assignable: person)

      get vacancy_path(show, token: token)

      expect(page.css("input[type='checkbox'][name='role_ids[]']").size).to eq(4)
      expect(page.text.squish).to include("You have 4 assignments in this show.", "Which assignments can't you make?")
      expect(page.at_css("button[data-vacancy-form-target='submit']").text.squish).to eq("I confirm that I can't make these 4 assignments")
    end
  end

  describe "confirming" do
    it "gives up the ticked acts, keeps the unticked one, and sends one notice for them all" do
      expect {
        post vacancy_confirm_path(show, token: token), params: { role_ids: [ key(act("Fan Dance")), key(act("Finale")) ] }
      }.to change(RoleVacancy, :count).by(2)
        .and have_enqueued_job(VacancyNotificationJob).exactly(:once)

      vacancies = RoleVacancy.order(:id).last(2)
      expect(vacancies.map { |v| v.role.name }).to eq([ "Fan Dance", "Finale" ])
      expect(vacancies.map(&:vacated_by)).to all(eq(person))
      expect(VacancyNotificationJob).to have_been_enqueued.with(vacancies.map(&:id), "created")
      expect(held).to eq([ "Aerial Hoop" ])
      expect(show.reload.casting_finalized?).to be(false)

      follow_redirect!
      expect(response).to have_http_status(:ok)
      text = page.text.squish
      expect(text).to include("We acknowledge that you can't make 2 of your acts.",
                              "The production team will be notified and will find replacements.")
      expect(page.css("[data-cant-make] p.text-sm").map(&:text)).to eq([ "Act 1 · Fan Dance", "Act 4 · Finale" ])
      expect(page.css("[data-still-performing] p.text-sm").map(&:text)).to eq([ "Act 3 · Aerial Hoop" ])
    end

    it "says so when every act is given up, with nothing left to perform" do
      post vacancy_confirm_path(show, token: token), params: { role_ids: [ "Fan Dance", "Aerial Hoop", "Finale" ].map { |name| key(act(name)) } }

      expect(held).to be_empty
      follow_redirect!
      expect(page.text.squish).to include("We acknowledge that you can't make your 3 acts.")
      expect(page.css("[data-cant-make] p.text-sm").size).to eq(3)
      expect(page.at_css("[data-still-performing]")).to be_nil
    end

    it "sends the one act's own notice, as before, when one act is given up" do
      expect {
        post vacancy_confirm_path(show, token: token), params: { role_ids: [ key(act("Finale")) ] }
      }.to change(RoleVacancy, :count).by(1)

      expect(VacancyNotificationJob).to have_been_enqueued.with(RoleVacancy.last.id, "created").exactly(:once)
      expect(held).to eq([ "Aerial Hoop", "Fan Dance" ])
      follow_redirect!
      expect(page.text.squish).to include("We acknowledge that you can't make 1 of your acts.",
                                          "The production team will be notified and will find a replacement.")
    end

    it "gives up nothing for someone else's act, or with nothing ticked" do
      other = create(:person, user: create(:user), name: "Other Performer")
      create(:show_person_role_assignment, show: show, role: act("Juggling"), assignable: other)

      expect {
        post vacancy_confirm_path(show, token: token), params: { role_ids: [ key(act("Juggling"), other) ] }
        post vacancy_confirm_path(show, token: token), params: {}
      }.not_to change(RoleVacancy, :count)

      expect(response).to redirect_to(vacancy_path(show, token: token))
      expect(show.show_person_role_assignments.where(assignable: other).count).to eq(1)
    end

    it "lets the performer come back for an act they kept, and lists only what is still held" do
      post vacancy_confirm_path(show, token: token), params: { role_ids: [ key(act("Fan Dance")), key(act("Finale")) ] }

      get vacancy_path(show, token: token)

      expect(page.css("input[type='checkbox'][name='role_ids[]']")).to be_empty
      expect(page.css("input[type='radio'][name='role_ids[]']").map { |radio| radio["value"] }).to eq([ key(act("Aerial Hoop")) ])
      expect(page.text.squish).to include("as Act 3 · Aerial Hoop")
      expect(page.text).not_to include("Fan Dance")

      # An act already given up can't be given up again.
      expect {
        post vacancy_confirm_path(show, token: token), params: { role_ids: [ key(act("Fan Dance")) ] }
      }.not_to change(RoleVacancy, :count)
    end
  end

  # Casting was finalized but Juniper never got a casting notice: once the
  # show's casting reopens, My Shows hides what Juniper holds, as it does for
  # everyone, and the row still names what was given up.
  it "names the acts given up on My Shows while the casting is reopened" do
    create(:talent_pool_membership, talent_pool: production.talent_pool, member: person)
    post vacancy_confirm_path(show, token: token), params: { role_ids: [ key(act("Fan Dance")), key(act("Finale")) ] }
    post handle_signin_path, params: { email_address: user.email_address, password: password }

    get my_shows_path

    expect(page.text.squish).to include("You've indicated that you can't make Act 1 · Fan Dance and Act 4 · Finale")
    expect(page.text.squish).not_to include("Can't make it?")
  end

  describe "the production team's notice" do
    before { ProductionNotificationSetting.create!(production: production, user: owner, enabled: true) }

    let!(:owner_person) { create(:person, user: owner, name: "Olive Owner").tap { |p| owner.update!(default_person: p) } }

    it "is one notification that names every act" do
      post vacancy_confirm_path(show, token: token), params: { role_ids: [ key(act("Finale")), key(act("Fan Dance")) ] }

      expect { perform_enqueued_jobs(only: VacancyNotificationJob) }.to change { Notification.where(user: owner).count }.by(1)

      notice = Notification.where(user: owner).last
      expect(notice).to have_attributes(kind: "vacancy_created_several", category: "casting",
                                        path: "/manage/casting/#{production.id}/#{show.id}/cast")
      expect(notice.title).to start_with("Juniper Vale can't make 2 acts on ")
      body = ActionController::Base.helpers.strip_tags(notice.body).squish
      expect(body).to include("Juniper Vale can't make 2 acts in The Velvet Hour", "Act 1 · Fan Dance and Act 4 · Finale.",
                              "A vacancy has been created for each one, and you can now invite replacements.")
    end

    it "stays the single act's notice for one act" do
      post vacancy_confirm_path(show, token: token), params: { role_ids: [ key(act("Finale")) ] }

      expect { perform_enqueued_jobs(only: VacancyNotificationJob) }.to change { Notification.where(user: owner).count }.by(1)
      expect(Notification.where(user: owner).last.kind).to eq("vacancy_created")
    end
  end

  describe "My Shows, after keeping an act" do
    # Juniper was notified of the casting, so the acts Juniper holds stay on
    # My Shows while the production team recasts the ones given up.
    before do
      create(:talent_pool_membership, talent_pool: production.talent_pool, member: person)
      ShowCastNotification.create!(show: show, assignable: person, notification_type: :cast, notified_at: Time.current)
      post vacancy_confirm_path(show, token: token), params: { role_ids: [ key(act("Fan Dance")), key(act("Finale")) ] }
      post handle_signin_path, params: { email_address: user.email_address, password: password }
    end

    it "keeps Can't make it? on the show's row and names the acts given up" do
      get my_shows_path

      expect(response).to have_http_status(:ok)
      expect(page.text.squish).to include("Can't make it?")
      expect(page.css("[data-vacancy-note]").map { |note| note.text.squish })
        .to eq([ "You've indicated that you can't make Act 1 · Fan Dance and Act 4 · Finale" ])
    end

    it "lists each act given up on the show's page with its own way back, beside the act still held" do
      get my_show_path(show)

      expect(response).to have_http_status(:ok)
      given_up = page.css("[data-given-up-vacancy]").map { |row| row.at_css("p").text.squish }
      expect(given_up).to eq([ "You've indicated that you can't make Act 1 · Fan Dance", "You've indicated that you can't make Act 4 · Finale" ])
      expect(page.css("[data-given-up-vacancy] button").map { |button| button.text.squish }.uniq).to include("Actually, I can make it")
      expect(page.css("a").map { |a| a.text.squish }).to include("Can't make it?")

      # Taking one back restores that act alone.
      post my_reclaim_vacancy_path(show, RoleVacancy.joins(:role).find_by!(roles: { name: "Finale" }))
      expect(held).to eq([ "Aerial Hoop", "Finale" ])
      get my_show_path(show)
      expect(page.css("[data-given-up-vacancy]").size).to eq(1)
    end
  end
end
