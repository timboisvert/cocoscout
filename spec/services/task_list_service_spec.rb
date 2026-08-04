# frozen_string_literal: true

require "rails_helper"

RSpec.describe TaskListService do
  let(:user) { create(:user) }
  let!(:person) { create(:person, user: user, name: "Main Person") }
  let(:organization) { create(:organization, :pro) }
  let(:production) { create(:production, organization: organization) }
  let(:pool) { create(:talent_pool, production: production) }

  def join_pool(member, talent_pool = pool)
    TalentPoolMembership.create!(talent_pool: talent_pool, member: member)
  end

  def service
    described_class.new(user)
  end

  describe "availability items" do
    before { join_pool(person) }

    it "treats a pooled future show with no availability row as an open task" do
      show = create(:show, production: production, date_and_time: 2.weeks.from_now)

      expect(service.open_availability_items.map { |i| i[:show] }).to eq([ show ])
      expect(service.counts[:availability]).to eq(1)
      expect(service.counts[:total]).to eq(1)
    end

    it "still counts a row with status 'unset' as awaiting (regression: a bare row used to count as answered)" do
      show = create(:show, production: production, date_and_time: 2.weeks.from_now)
      create(:show_availability, show: show, available_entity: person, status: :unset)

      expect(service.open_availability_items.map { |i| i[:show] }).to eq([ show ])
      expect(service.answered_availability_items).to be_empty
    end

    it "moves answered shows to answered_availability_items and out of the counts" do
      yes_show = create(:show, production: production, date_and_time: 2.weeks.from_now)
      no_show  = create(:show, production: production, date_and_time: 3.weeks.from_now)
      create(:show_availability, :available, show: yes_show, available_entity: person)
      create(:show_availability, :unavailable, show: no_show, available_entity: person)

      expect(service.open_availability_items).to be_empty
      expect(service.answered_availability_items.map { |i| i[:show] }).to eq([ yes_show, no_show ])
      expect(service.counts[:availability]).to eq(0)
    end

    it "uses the unified 120-day window (a 100-day-out show counts; 121 days doesn't)" do
      counted  = create(:show, production: production, date_and_time: 100.days.from_now)
      create(:show, production: production, date_and_time: 121.days.from_now)

      expect(service.open_availability_items.map { |i| i[:show] }).to eq([ counted ])
    end

    it "excludes past, canceled, and course-production shows" do
      create(:show, production: production, date_and_time: 1.week.ago)
      create(:show, production: production, date_and_time: 1.week.from_now, canceled: true)
      course_production = create(:production, organization: production.organization, production_type: "course")
      course_pool = create(:talent_pool, production: course_production)
      join_pool(person, course_pool)
      create(:show, production: course_production, date_and_time: 1.week.from_now)

      expect(service.open_availability_items).to be_empty
    end
  end

  describe "the four pool-reach paths and per show x entity counting" do
    it "reaches shows via a person's directly-owned pool and via a shared pool" do
      join_pool(person)
      direct_show = create(:show, production: production, date_and_time: 1.week.from_now)

      other_production = create(:production, organization: production.organization)
      create(:talent_pool_share, talent_pool: pool, production: other_production)
      shared_show = create(:show, production: other_production, date_and_time: 2.weeks.from_now)

      expect(service.open_availability_items.map { |i| i[:show] }).to contain_exactly(direct_show, shared_show)
    end

    it "reaches shows via a group's direct and shared pools, and counts the same show once per entity" do
      group = create(:group)
      create(:group_membership, group: group, person: person)
      join_pool(person)
      join_pool(group)
      show = create(:show, production: production, date_and_time: 1.week.from_now)

      other_production = create(:production, organization: production.organization)
      group_pool = create(:talent_pool, production: other_production)
      join_pool(group, group_pool)
      third_production = create(:production, organization: production.organization)
      create(:talent_pool_share, talent_pool: group_pool, production: third_production)
      group_shared_show = create(:show, production: third_production, date_and_time: 2.weeks.from_now)

      items = service.open_availability_items
      # The first show is reachable by BOTH the person and the group — two tasks.
      expect(items.select { |i| i[:show] == show }.map { |i| i[:entity_key] })
        .to contain_exactly("person_#{person.id}", "group_#{group.id}")
      # The group-only shows appear once each, for the group.
      group_pool_show_items = items.select { |i| i[:show] == group_shared_show }
      expect(group_pool_show_items.map { |i| i[:entity_key] }).to eq([ "group_#{group.id}" ])
      expect(service.counts[:availability]).to eq(items.size)
    end
  end

  describe "sign-up items" do
    before { join_pool(person) }

    let!(:show) { create(:show, production: production, date_and_time: 2.weeks.from_now) }
    let(:form) { create(:sign_up_form, production: production) }
    let!(:instance) { create(:sign_up_form_instance, sign_up_form: form, show: show, status: "open") }

    it "classifies a show with an open sign-up form as a sign-up task, not availability" do
      expect(service.open_signup_items.map { |i| i[:show] }).to eq([ show ])
      expect(service.open_availability_items).to be_empty
      expect(service.counts).to include(signups: 1, availability: 0)
    end

    it "moves a registered person to answered_signup_items but keeps the item visible" do
      slot = create(:sign_up_slot, sign_up_form: form, sign_up_form_instance: instance)
      create(:sign_up_registration, sign_up_slot: slot, sign_up_form_instance: instance, person: person)

      expect(service.open_signup_items).to be_empty
      answered = service.answered_signup_items
      expect(answered.map { |i| i[:show] }).to eq([ show ])
      expect(answered.first[:registration]).to be_present
      expect(service.counts[:signups]).to eq(0)
    end

    it "treats an unavailable answer or a cancelled registration as declined (answered, not open)" do
      create(:show_availability, :unavailable, show: show, available_entity: person)

      expect(service.open_signup_items).to be_empty
      expect(service.answered_signup_items.first[:declined]).to be(true)
    end

    it "hides scheduled instances unless talent pre-registration is open" do
      instance.update!(status: "scheduled")
      form.update!(pre_registration_mode: "disabled")

      expect(service.open_signup_items).to be_empty
      expect(service.open_availability_items).to be_empty # show is skipped entirely
    end

    it "treats a show whose only form is archived as an availability request" do
      form.update!(archived_at: Time.current)

      expect(service.open_signup_items).to be_empty
      expect(service.open_availability_items.map { |i| i[:show] }).to eq([ show ])
    end

    it "never produces sign-up items for groups" do
      group = create(:group)
      create(:group_membership, group: group, person: person)
      join_pool(group)

      keys = (service.open_signup_items + service.answered_signup_items).map { |i| i[:entity_key] }
      expect(keys).to eq([ "person_#{person.id}" ])
    end
  end

  describe "questionnaires" do
    before { join_pool(person) }

    let(:questionnaire) { create(:questionnaire, production: production) }

    it "lists an invited, unanswered questionnaire as open" do
      QuestionnaireInvitation.create!(questionnaire: questionnaire, invitee: person)

      expect(service.open_questionnaire_items.map { |i| i[:questionnaire] }).to eq([ questionnaire ])
      expect(service.counts[:questionnaires]).to eq(1)
    end

    it "moves responded questionnaires to completed and out of the counts" do
      QuestionnaireInvitation.create!(questionnaire: questionnaire, invitee: person)
      QuestionnaireResponse.create!(questionnaire: questionnaire, respondent: person)

      expect(service.open_questionnaire_items).to be_empty
      expect(service.completed_questionnaire_items.map { |i| i[:questionnaire] }).to eq([ questionnaire ])
      expect(service.counts[:questionnaires]).to eq(0)
    end

    it "excludes archived and not-accepting questionnaires entirely" do
      archived = create(:questionnaire, production: production, archived_at: Time.current)
      closed = create(:questionnaire, production: production, accepting_responses: false)
      QuestionnaireInvitation.create!(questionnaire: archived, invitee: person)
      QuestionnaireInvitation.create!(questionnaire: closed, invitee: person)

      expect(service.open_questionnaire_items).to be_empty
      expect(service.completed_questionnaire_items).to be_empty
    end
  end

  describe "non-event (shared_pool) sign-ups" do
    before { join_pool(person) }

    it "lists them for display but never counts them as open tasks" do
      form = create(:sign_up_form, :shared_pool, production: production)
      slot = create(:sign_up_slot, sign_up_form: form)
      create(:sign_up_registration, sign_up_slot: slot, person: person)

      expect(service.non_event_signups.map { |i| i[:form] }).to eq([ form ])
      expect(service.counts[:total]).to eq(0)
    end
  end

  describe "entity filter" do
    it "restricts items to the selected people" do
      join_pool(person)
      second = create(:person, user: user, name: "Second Person")
      join_pool(second)
      create(:show, production: production, date_and_time: 1.week.from_now)

      filtered = described_class.new(user, selected_person_ids: [ second.id ], selected_group_ids: [])
      expect(filtered.open_availability_items.map { |i| i[:entity_key] }).to eq([ "person_#{second.id}" ])
    end
  end

  describe "counts parity (badge mode == page mode)" do
    it "returns the same total from badge mode, details mode, and the sum of the open lists" do
      join_pool(person)
      create(:show, production: production, date_and_time: 1.week.from_now)   # open availability
      answered = create(:show, production: production, date_and_time: 2.weeks.from_now)
      create(:show_availability, :available, show: answered, available_entity: person)

      signup_show = create(:show, production: production, date_and_time: 3.weeks.from_now)
      form = create(:sign_up_form, production: production)
      create(:sign_up_form_instance, sign_up_form: form, show: signup_show, status: "open")

      questionnaire = create(:questionnaire, production: production)
      QuestionnaireInvitation.create!(questionnaire: questionnaire, invitee: person)

      full = described_class.new(user)
      open_sum = full.open_availability_items.size + full.open_signup_items.size + full.open_questionnaire_items.size

      expect(full.counts[:total]).to eq(3)
      expect(open_sum).to eq(3)
      expect(described_class.open_count(user)).to eq(3)
    end
  end

  describe "#any_productions?" do
    it "is false with no pool membership and true with one" do
      expect(service.any_productions?).to be(false)
      join_pool(person)
      expect(described_class.new(user).any_productions?).to be(true)
    end
  end

  describe ".build_signup_item" do
    before { join_pool(person) }

    it "computes declined from an unavailable answer when not passed" do
      show = create(:show, production: production, date_and_time: 1.week.from_now)
      create(:show_availability, :unavailable, show: show, available_entity: person)

      item = described_class.build_signup_item(show, person, nil, nil)
      expect(item[:declined]).to be(true)
      expect(item[:entity_key]).to eq("person_#{person.id}")
    end
  end
end
