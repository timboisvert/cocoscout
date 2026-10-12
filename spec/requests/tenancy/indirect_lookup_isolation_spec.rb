# frozen_string_literal: true

require "rails_helper"

# Cross-org holes the CocoScout/UnscopedFind cop can't see: the foreign id
# arrives through a local variable, a mass-assigned foreign key, or a param
# key name (availability_<show_id>) rather than a literal Model.find(params).
# Found in the Oct 2026 Pro-tier security review. Same shape as
# cross_org_isolation_spec: an org-A manager, their own production id in the
# URL, and org B's ids in the request.
RSpec.describe "Cross-org isolation: indirect lookups (manage)", type: :request do
  let(:password) { "Password123!" }

  let(:attacker) { create(:user, password: password) }
  let!(:attacker_person) { create(:person, user: attacker).tap { |p| attacker.update!(default_person: p) } }
  let!(:org) { create(:organization, :pro, owner: attacker) }
  let!(:org_role) { create(:organization_role, :manager, user: attacker, organization: org) }
  let!(:production) { create(:production, organization: org) }
  let!(:my_show) { create(:show, production: production) }
  let!(:my_person) { create(:person).tap { |p| org.people << p } }

  let(:victim_owner) { create(:user) }
  let!(:victim_org) { create(:organization, :pro, owner: victim_owner) }
  let!(:victim_production) { create(:production, organization: victim_org) }
  let!(:victim_show) { create(:show, production: victim_production) }
  let!(:victim_person) { create(:person).tap { |p| victim_org.people << p } }

  before do
    org.people << attacker_person unless org.people.include?(attacker_person)
    post handle_signin_path, params: { email_address: attacker.email_address, password: password }
  end

  describe "audition detail through a foreign session id" do
    let!(:my_cycle) { create(:audition_cycle, production: production, active: true) }
    let!(:victim_cycle) { create(:audition_cycle, production: victim_production) }
    let!(:victim_session) { create(:audition_session, audition_cycle: victim_cycle) }
    let!(:victim_request) { create(:audition_request, audition_cycle: victim_cycle) }
    let!(:victim_audition) do
      create(:audition, audition_request: victim_request, audition_session: victim_session,
                        auditionable: victim_request.requestable)
    end

    it "404s reading a foreign audition (answers, reviewers' comments) via my cycle" do
      get manage_signups_auditions_cycle_session_audition_path(production, my_cycle, victim_session, victim_audition)
      expect(response).to have_http_status(:not_found)
    end

    it "404s voting on a foreign audition via my cycle" do
      expect {
        post manage_cast_vote_signups_auditions_cycle_session_audition_path(production, my_cycle, victim_session, victim_audition),
             params: { vote: "no", comment: "planted" }
      }.not_to change(AuditionVote, :count)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "show update" do
    it "ignores a production_id that would move my show into another org" do
      patch manage_update_show_path(production, my_show), params: { show: { production_id: victim_production.id } }
      expect(my_show.reload.production_id).to eq(production.id)
    end
  end

  describe "audition cycle update" do
    let!(:my_cycle) { create(:audition_cycle, production: production) }

    it "ignores a production_id that would move my cycle into another org" do
      patch manage_update_signups_auditions_cycle_path(production, my_cycle),
            params: { audition_cycle: { production_id: victim_production.id } }
      expect(my_cycle.reload.production_id).to eq(production.id)
    end

    it "ignores a questionable that would move my question onto another org's form" do
      victim_cycle = create(:audition_cycle, production: victim_production)
      question = create(:question, questionable: my_cycle)

      patch manage_update_question_signups_auditions_cycle_path(production, my_cycle, question),
            params: { question: { text: "Renamed", questionable_type: "AuditionCycle", questionable_id: victim_cycle.id } }

      expect(question.reload.questionable).to eq(my_cycle)
    end
  end

  describe "messages to a talent pool" do
    let!(:victim_pool) { create(:talent_pool, production: victim_production) }

    before do
      victim_person.update!(user: create(:user))
      TalentPoolMembership.create!(talent_pool: victim_pool, member: victim_person)
    end

    it "refuses to message every member of a foreign org's talent pool" do
      expect {
        post manage_messages_path, params: { recipient_type: "talent_pool", recipient_id: victim_pool.id,
                                             subject: "Hello", body: "From another org" }
      }.not_to change(Message, :count)
      # The controller turns RecordNotFound into a redirect back to Messages.
      expect(response).to redirect_to(manage_messages_path)
      expect(flash[:alert]).to eq("Message not found")
    end
  end

  describe "contact availability" do
    let!(:my_group) { create(:group).tap { |g| org.groups << g } }

    it "won't write my person's availability onto a foreign org's show" do
      expect {
        patch manage_update_availability_contacts_person_path(my_person),
              params: { "availability_#{victim_show.id}" => "available" }
      }.not_to change(ShowAvailability, :count)
    end

    it "won't write my group's availability onto a foreign org's show" do
      expect {
        patch manage_update_availability_contacts_group_path(my_group),
              params: { "availability_#{victim_show.id}" => "available" }
      }.not_to change(ShowAvailability, :count)
    end
  end

  describe "casting availability grid" do
    it "404s writing a foreign org's person onto my show's availability" do
      expect {
        patch manage_update_show_availability_casting_availability_path(production, my_show),
              params: { "availability_Person_#{victim_person.id}" => "available" }
      }.not_to change(ShowAvailability, :count)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "vacancy fill" do
    let!(:role) { create(:role, production: production) }
    let!(:vacancy) { create(:role_vacancy, show: my_show, role: role) }

    it "404s filling my vacancy with a foreign org's person" do
      post manage_fill_casting_vacancy_path(production, vacancy), params: { person_id: victim_person.id }

      expect(response).to have_http_status(:not_found)
      expect(vacancy.reload.status).to eq("open")
    end
  end

  describe "casting table wizard, members chosen by hand" do
    before { my_show.update!(casting_enabled: true) }

    it "drops people and groups that aren't in my organization" do
      post manage_casting_tables_save_productions_path, params: { production_ids: [ production.id ] }
      post manage_casting_tables_save_events_path, params: { show_ids: [ my_show.id ] }
      post manage_casting_tables_save_members_path,
           params: { member_source: "manual", person_ids: [ victim_person.id, my_person.id ] }
      post manage_casting_tables_create_path, params: { name: "Fall" }

      members = CastingTableMember.where(memberable_type: "Person").pluck(:memberable_id)
      expect(members).to include(my_person.id)
      expect(members).not_to include(victim_person.id)
    end
  end

  describe "advances (Money)" do
    it "404s issuing an advance to a foreign org's person" do
      expect {
        post manage_create_money_production_advance_path(production),
             params: { person_advance: { person_id: victim_person.id, original_amount: "50" } }
      }.not_to change(PersonAdvance, :count)
      expect(response).to have_http_status(:not_found)
    end

    it "404s recording a waiver on a foreign org's show" do
      expect {
        post manage_create_money_advance_waiver_path(production),
             params: { show_advance_waiver: { show_id: victim_show.id, person_id: my_person.id, reason: "performer_declined" } }
      }.not_to change(ShowAdvanceWaiver, :count)
      expect(response).to have_http_status(:not_found)
    end

    it "skips a foreign org's person when issuing show advances" do
      ShowPayout.create!(show: my_show, status: "awaiting_payout")

      expect {
        post manage_issue_advances_money_show_payout_path(my_show),
             params: { advances: { "0" => { person_id: victim_person.id, amount: "25" } } }
      }.not_to change(PersonAdvance, :count)
    end
  end

  describe "show payout calculation (Money)" do
    let!(:victim_scheme) do
      PayoutScheme.create!(
        organization: victim_org, name: "Their Split",
        rules: {
          "allocation" => [ { "type" => "percentage", "value" => 40.0, "label" => "House take" }, { "type" => "remainder" } ],
          "distribution" => { "method" => "shares", "default_shares" => 1.0 }
        }
      )
    end
    let!(:my_payout) { ShowPayout.create!(show: my_show, status: "awaiting_payout") }

    it "404s pointing my show's payout at a foreign org's calculation" do
      patch manage_money_show_payout_path(my_show), params: { show_payout: { payout_scheme_id: victim_scheme.id } }

      expect(response).to have_http_status(:not_found)
      expect(my_payout.reload.payout_scheme_id).to be_nil
    end
  end

  describe "production agreement template (Agreements)" do
    let!(:victim_template) do
      AgreementTemplate.create!(organization: victim_org, name: "Their terms", content: "<p>Confidential terms</p>")
    end

    it "won't attach another org's agreement template to my production" do
      patch manage_production_path(production),
            params: { production: { agreement_template_id: victim_template.id, agreement_required: "1" } }
      expect(production.reload.agreement_template_id).to be_nil
    end
  end

  describe "staffing: add a staff member (Staffing)" do
    it "404s adding a foreign org's person as my staff" do
      expect {
        post manage_create_staffing_staff_path, params: { person_id: victim_person.id }
      }.not_to change(OrganizationStaffMember, :count)
      expect(response).to have_http_status(:not_found)
    end
  end
end
