# frozen_string_literal: true

require "rails_helper"

# Switching a lineup from roles to acts must lose nothing: a role holding five
# people becomes five single-slot acts in a row, each person still cast once,
# on their own act, with their notification (and any vacancy) following.
RSpec.describe CastingModeConverter do
  let(:org) { create(:organization) }
  let(:production) { create(:production, organization: org, casting_mode: "role_based") }
  let(:show) { create(:show, production: production, date_and_time: 3.days.from_now) }
  let(:later_show) { create(:show, production: production, date_and_time: 10.days.from_now) }

  let!(:dancer) { create(:role, production: production, name: "Dancer", quantity: 5, position: 0) }
  let!(:host)   { create(:role, production: production, name: "Host", quantity: 1, position: 1) }

  let(:dancers) { (1..5).map { |i| create(:person, name: "Dancer #{i}").tap { |p| org.people << p } } }
  let(:mc)      { create(:person, name: "The MC").tap { |p| org.people << p } }

  def cast!(a_show, role, person, slot)
    create(:show_person_role_assignment, show: a_show, role: role, assignable: person, position: slot)
  end

  def cast_of(a_show)
    a_show.show_person_role_assignments.reload.includes(:role).map do |a|
      [ a.assignable.name, a.role.name, a.role.position, a.position ]
    end
  end

  before do
    dancers.each_with_index { |p, i| cast!(show, dancer, p, i + 1) }
    cast!(show, host, mc, 1)
  end

  describe ".to_acts! (a production switching to acts)" do
    def convert!
      production.update!(casting_mode: "act_based")
      described_class.to_acts!(production)
    end

    it "splits Dancer ×5 into five Dancer acts, then Host, in running order" do
      summary = convert!

      lineup = production.roles.production_roles.reload
      expect(lineup.map(&:name)).to eq(%w[Dancer Dancer Dancer Dancer Dancer Host])
      expect(lineup.map(&:position)).to eq([ 0, 1, 2, 3, 4, 5 ])
      expect(lineup.map(&:quantity)).to all(eq(1))
      expect(lineup.first.id).to eq(dancer.id) # the original role is the first act
      expect(host.reload.position).to eq(5)
      expect(summary.roles_split).to eq(1)
      expect(summary.acts_created).to eq(4)
      expect(summary.assignments_moved).to eq(4)
    end

    it "keeps every person cast exactly once, each on their own act, slot order preserved" do
      convert!

      lineup = production.roles.production_roles.reload.to_a
      cast = cast_of(show)
      expect(cast.size).to eq(6)
      dancers.each_with_index do |person, i|
        expect(cast).to include([ person.name, "Dancer", i, 1 ])
      end
      expect(cast).to include([ "The MC", "Host", 5, 1 ])
      # one assignment per act, none doubled up
      expect(show.show_person_role_assignments.reload.group(:role_id).count.values).to all(eq(1))
      expect(show.show_person_role_assignments.map(&:role_id).sort).to eq(lineup.map(&:id).sort)
    end

    it "moves each person's cast notification to the act they now hold, so nobody reads as newly cast" do
      dancers.each { |p| ShowCastNotification.create!(show: show, role: dancer, assignable: p, notified_at: 1.day.ago, notification_type: :cast) }
      ShowCastNotification.create!(show: show, role: host, assignable: mc, notified_at: 1.day.ago, notification_type: :cast)

      summary = convert!

      expect(summary.notifications_moved).to eq(4)
      show.show_person_role_assignments.reload.each do |a|
        expect(ShowCastNotification.where(show: show, assignable: a.assignable, role_id: a.role_id).count).to eq(1)
      end
      expect(ShowCastNotification.where(show: show).count).to eq(6)
    end

    it "moves a vacancy with the person who opened it" do
      vacancy = create(:role_vacancy, show: show, role: dancer, vacated_by: dancers[2], status: "open")
      unattributed = create(:role_vacancy, show: show, role: dancer, status: "open")

      summary = convert!

      third_act = show.show_person_role_assignments.find_by(assignable: dancers[2]).role
      expect(third_act.id).not_to eq(dancer.id)
      expect(vacancy.reload.role_id).to eq(third_act.id)
      expect(unattributed.reload.role_id).to eq(dancer.id)
      expect(summary.vacancies_moved).to eq(1)
    end

    it "is idempotent — running it again changes nothing" do
      convert!
      before_roles = production.roles.production_roles.reload.map { |r| [ r.id, r.name, r.position, r.quantity ] }
      before_cast = cast_of(show)

      summary = described_class.to_acts!(production)

      expect(summary).not_to be_changed
      expect(production.roles.production_roles.reload.map { |r| [ r.id, r.name, r.position, r.quantity ] }).to eq(before_roles)
      expect(cast_of(show)).to eq(before_cast)
    end

    it "copies restriction and eligibilities onto every new act" do
      eligible = dancers.first(2)
      dancer.update_columns(restricted: true)
      eligible.each { |p| dancer.role_eligibilities.create!(member: p) }

      convert!

      production.roles.production_roles.reload.select { |r| r.name == "Dancer" }.each do |act|
        expect(act).to be_restricted
        expect(act.role_eligibilities.map(&:member_id)).to match_array(eligible.map(&:id))
      end
      expect(host.reload).not_to be_restricted
    end

    it "leaves quantity-1 roles and breaks alone" do
      production.update!(casting_mode: "act_based")
      intermission = production.roles.create!(name: "Intermission", category: "break", position: 1)
      host.update!(position: 2)

      described_class.to_acts!(production)

      expect(intermission.reload.category).to eq("break")
      expect(production.roles.production_roles.reload.map(&:name)).to eq(%w[Dancer Dancer Dancer Dancer Dancer Intermission Host])
      expect(host.reload.quantity).to eq(1)
      expect(host.show_person_role_assignments.count).to eq(1)
    end

    it "keeps assignments on every show that casts from the production's roles" do
      cast!(later_show, dancer, dancers[3], 1)
      cast!(later_show, dancer, dancers[0], 4)

      convert!

      lineup = production.roles.production_roles.reload.to_a
      expect(cast_of(later_show)).to contain_exactly(
        [ dancers[3].name, "Dancer", 0, 1 ],
        [ dancers[0].name, "Dancer", 3, 1 ]
      )
      expect(later_show.show_person_role_assignments.map(&:role_id)).to all(be_in(lineup.map(&:id)))
      expect(cast_of(show).size).to eq(6)
    end

    it "makes room for a night that had more people cast than the role's quantity" do
      dancer.update_columns(quantity: 3)

      convert!

      expect(production.roles.production_roles.reload.count { |r| r.name == "Dancer" }).to eq(5)
      expect(cast_of(show).size).to eq(6)
      expect(show.show_person_role_assignments.reload.group(:role_id).count.values).to all(eq(1))
    end

    it "assigns a slot to legacy assignments with no position, without doubling up" do
      show.show_person_role_assignments.where(assignable: dancers[1]).update_all(position: 0)
      show.show_person_role_assignments.where(assignable: dancers[4]).update_all(position: 0)

      convert!

      expect(show.show_person_role_assignments.reload.group(:role_id).count.values).to all(eq(1))
      expect(show.show_person_role_assignments.map(&:position)).to all(eq(1))
      expect(cast_of(show).size).to eq(6)
    end

    it "converts the custom lineup of a show that inherits the production's mode, and only that show's" do
      custom_show = create(:show, production: production, use_custom_roles: true, date_and_time: 5.days.from_now)
      duo = create(:role, production: production, show: custom_show, name: "Duo", quantity: 2, position: 0)
      cast!(custom_show, duo, dancers[0], 1)
      cast!(custom_show, duo, dancers[1], 2)
      pinned_show = create(:show, production: production, use_custom_roles: true, casting_mode: "role_based", date_and_time: 6.days.from_now)
      trio = create(:role, production: production, show: pinned_show, name: "Trio", quantity: 3, position: 0)
      cast!(pinned_show, trio, dancers[2], 1)

      convert!

      expect(custom_show.custom_roles.reload.map { |r| [ r.name, r.quantity ] }).to eq([ [ "Duo", 1 ], [ "Duo", 1 ] ])
      expect(cast_of(custom_show)).to contain_exactly([ dancers[0].name, "Duo", 0, 1 ], [ dancers[1].name, "Duo", 1, 1 ])
      # the show that pins role mode didn't flip, so its lineup is untouched
      expect(pinned_show.custom_roles.reload.map { |r| [ r.name, r.quantity ] }).to eq([ [ "Trio", 3 ] ])
      expect(cast_of(pinned_show)).to eq([ [ dancers[2].name, "Trio", 0, 1 ] ])
    end

    it "leaves draft casting-table assignments on the original role" do
      table = CastingTable.create!(organization: org, name: "Draft")
      table.casting_table_draft_assignments.create!(show: show, role: dancer, assignable: dancers[4])

      convert!

      expect(table.casting_table_draft_assignments.reload.map(&:role_id)).to eq([ dancer.id ])
    end

    it "refuses to run on a production that isn't act-based" do
      expect { described_class.to_acts!(production) }.to raise_error(ArgumentError)
    end
  end

  describe ".to_acts_for_show! (one show overriding to acts)" do
    def convert!(a_show)
      a_show.update!(casting_mode: "act_based")
      described_class.to_acts_for_show!(a_show)
    end

    it "gives the show its own lineup with its cast carried over, split into acts, and leaves the production's roles alone" do
      cast!(later_show, dancer, dancers[3], 2)
      ShowCastNotification.create!(show: show, role: dancer, assignable: dancers[2], notified_at: 1.day.ago, notification_type: :cast)

      summary = convert!(show)

      expect(summary.lineups_copied).to eq(1)
      expect(show.reload).to be_use_custom_roles
      expect(show.custom_roles.reload.map(&:name)).to eq(%w[Dancer Dancer Dancer Dancer Dancer Host])
      expect(show.custom_roles.map(&:quantity)).to all(eq(1))
      expect(cast_of(show).size).to eq(6)
      expect(show.show_person_role_assignments.map(&:role_id)).to all(be_in(show.custom_roles.map(&:id)))
      dancers.each_with_index { |p, i| expect(cast_of(show)).to include([ p.name, "Dancer", i, 1 ]) }
      third_act = show.show_person_role_assignments.find_by(assignable: dancers[2]).role
      expect(ShowCastNotification.find_by(show: show, assignable: dancers[2]).role_id).to eq(third_act.id)

      # production roles and the sibling show: exactly as they were
      expect(production.roles.production_roles.reload.map { |r| [ r.name, r.quantity ] }).to eq([ [ "Dancer", 5 ], [ "Host", 1 ] ])
      expect(cast_of(later_show)).to eq([ [ dancers[3].name, "Dancer", 0, 2 ] ])
      expect(later_show.reload).not_to be_use_custom_roles
    end

    it "keeps sharing the production's lineup when no role holds more than one person" do
      dancer.update_columns(quantity: 1)
      show.show_person_role_assignments.where(role: dancer).where.not(assignable: dancers[0]).delete_all

      summary = convert!(show)

      expect(summary).not_to be_changed
      expect(show.reload).not_to be_use_custom_roles
      expect(cast_of(show).size).to eq(2)
    end

    it "splits a show that already has its own custom lineup, and only that show's" do
      custom_show = create(:show, production: production, use_custom_roles: true, date_and_time: 5.days.from_now)
      duo = create(:role, production: production, show: custom_show, name: "Duo", quantity: 2, position: 0)
      cast!(custom_show, duo, dancers[0], 1)
      cast!(custom_show, duo, dancers[1], 2)

      convert!(custom_show)

      expect(custom_show.custom_roles.reload.map { |r| [ r.name, r.quantity ] }).to eq([ [ "Duo", 1 ], [ "Duo", 1 ] ])
      expect(cast_of(custom_show)).to contain_exactly([ dancers[0].name, "Duo", 0, 1 ], [ dancers[1].name, "Duo", 1, 1 ])
      expect(dancer.reload.quantity).to eq(5)
      expect(cast_of(show).size).to eq(6)
    end
  end

  describe "acts → roles" do
    it "loses nothing: every act stays a role and every assignment stays put" do
      production.update!(casting_mode: "act_based")
      described_class.to_acts!(production)
      roles_before = production.roles.production_roles.reload.map { |r| [ r.id, r.name, r.position, r.quantity ] }
      cast_before = cast_of(show)

      production.update!(casting_mode: "role_based")

      expect(production.roles.production_roles.reload.map { |r| [ r.id, r.name, r.position, r.quantity ] }).to eq(roles_before)
      expect(cast_of(show)).to eq(cast_before)
      expect(production.roles.production_roles.map(&:name)).to eq(%w[Dancer Dancer Dancer Dancer Dancer Host])
    end
  end
end
