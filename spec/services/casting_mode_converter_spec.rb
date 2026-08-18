# frozen_string_literal: true

require "rails_helper"

# Switching a lineup from roles to acts must lose nothing: a role holding five
# people becomes five single-slot acts in a row, each person still cast once,
# on their own act, with their notification (and any vacancy) following. And
# back again: the five acts fold into Dancer ×5 with everyone in a slot.
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

    it "moves a vacancy with the person who opened it, and leaves slot 1's own vacancy on act 1" do
      vacancy = create(:role_vacancy, show: show, role: dancer, vacated_by: dancers[2], status: "open")
      first_slot_vacancy = create(:role_vacancy, show: show, role: dancer, vacated_by: dancers[0], status: "open")

      summary = convert!

      third_act = show.show_person_role_assignments.find_by(assignable: dancers[2]).role
      expect(third_act.id).not_to eq(dancer.id)
      expect(vacancy.reload.role_id).to eq(third_act.id)
      # dancers[0] is still cast in slot 1, so their vacancy stays with them
      expect(first_slot_vacancy.reload.role_id).to eq(dancer.id)
      expect(summary.vacancies_moved).to eq(1)
    end

    it "seats an open vacancy nobody's assignment accounts for on the empty act, so filling it fills that act" do
      # Dancer ×5, four cast (slots 1–4); the fifth dancer bowed out and their
      # assignment is gone, leaving an open vacancy on the role.
      show.show_person_role_assignments.find_by(assignable: dancers[4]).destroy!
      vacancy = create(:role_vacancy, show: show, role: dancer, vacated_by: dancers[4], status: "open")
      unattributed = create(:role_vacancy, show: later_show, role: dancer, status: "open")
      cast!(later_show, dancer, dancers[0], 1)
      newcomer = create(:person, name: "New Dancer").tap { |p| org.people << p }

      summary = convert!

      acts = production.roles.production_roles.reload.select { |r| r.name == "Dancer" }
      empty_act = acts.find { |a| a.show_person_role_assignments.where(show: show).none? }
      expect(empty_act).to eq(acts.last)
      expect(vacancy.reload.role_id).to eq(empty_act.id)
      # on the other night only slot 1 is taken, so its vacancy takes act 2
      expect(unattributed.reload.role_id).to eq(acts[1].id)
      expect(summary.vacancies_moved).to eq(2)

      vacancy.fill!(newcomer)
      expect(show.show_person_role_assignments.reload.find_by(assignable: newcomer).role_id).to eq(empty_act.id)
      expect(show.show_person_role_assignments.group(:role_id).count.values).to all(eq(1))
    end

    it "gives a show that pins role mode its own copy of the production's roles, cast kept, before the split" do
      pinned = create(:show, production: production, casting_mode: "role_based", date_and_time: 7.days.from_now)
      cast!(pinned, dancer, dancers[1], 2)
      cast!(pinned, host, mc, 1)
      ShowCastNotification.create!(show: pinned, role: dancer, assignable: dancers[1], notified_at: 1.day.ago, notification_type: :cast)

      summary = convert!

      expect(summary.lineups_copied).to eq(1)
      pinned.reload
      expect(pinned).to be_use_custom_roles
      expect(pinned.custom_roles.map { |r| [ r.name, r.quantity ] }).to eq([ [ "Dancer", 5 ], [ "Host", 1 ] ])
      expect(cast_of(pinned)).to contain_exactly([ dancers[1].name, "Dancer", 0, 2 ], [ "The MC", "Host", 1, 1 ])
      expect(pinned.show_person_role_assignments.map(&:role_id)).to all(be_in(pinned.custom_roles.map(&:id)))
      expect(ShowCastNotification.find_by(show: pinned, assignable: dancers[1]).role_id).to eq(pinned.custom_roles.first.id)
      expect(pinned.custom_roles).to all(be_valid)
      # the production's own lineup still split for everyone else
      expect(production.roles.production_roles.reload.map(&:name)).to eq(%w[Dancer Dancer Dancer Dancer Dancer Host])
      expect(cast_of(show).size).to eq(6)
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

  describe ".to_roles! (a production switching back to roles)" do
    def to_acts!
      production.update!(casting_mode: "act_based")
      described_class.to_acts!(production)
    end

    def to_roles!
      production.update!(casting_mode: "role_based")
      described_class.to_roles!(production)
    end

    it "round-trips: five Dancer acts fold back into Dancer ×5 (same id), everyone in a slot, Host after" do
      to_acts!
      summary = to_roles!

      lineup = production.roles.production_roles.reload
      expect(lineup.map { |r| [ r.id, r.name, r.position, r.quantity ] }).to eq([ [ dancer.id, "Dancer", 0, 5 ], [ host.id, "Host", 1, 1 ] ])
      expect(lineup).to all(be_valid)
      cast = show.show_person_role_assignments.reload.includes(:role)
      expect(cast.size).to eq(6)
      dancer_slots = cast.select { |a| a.role_id == dancer.id }
      expect(dancer_slots.map(&:position)).to contain_exactly(1, 2, 3, 4, 5)
      dancers.each_with_index { |p, i| expect(dancer_slots.find { |a| a.assignable == p }.position).to eq(i + 1) }
      expect(cast.find { |a| a.assignable == mc }.role_id).to eq(host.id)
      expect(summary.roles_merged).to eq(1)
      expect(summary.acts_merged).to eq(4)
      expect(summary.assignments_moved).to eq(4)
      expect(Role.where(production: production).count).to eq(2)
    end

    it "brings notifications and vacancies back onto the merged role, and re-slots every night" do
      dancers.each { |p| ShowCastNotification.create!(show: show, role: dancer, assignable: p, notified_at: 1.day.ago, notification_type: :cast) }
      cast!(later_show, dancer, dancers[3], 1)
      cast!(later_show, dancer, dancers[0], 4)
      to_acts!
      fourth_act = show.show_person_role_assignments.find_by(assignable: dancers[3]).role
      vacancy = create(:role_vacancy, show: show, role: fourth_act, vacated_by: dancers[3], status: "open")

      summary = to_roles!

      expect(ShowCastNotification.where(show: show, role_id: dancer.id).count).to eq(5)
      expect(vacancy.reload.role_id).to eq(dancer.id)
      expect(summary.notifications_moved).to eq(4)
      expect(cast_of(later_show)).to contain_exactly([ dancers[3].name, "Dancer", 0, 1 ], [ dancers[0].name, "Dancer", 0, 2 ])
    end

    it "only merges acts that are in a row; other repeats get a suffix so role names stay unique" do
      to_acts!
      lineup = production.roles.production_roles.reload.to_a
      lineup[1].update_columns(name: "Solo")            # Dancer Solo Dancer Dancer Dancer Host
      lineup[4].update_columns(category: "technical")   # last Dancer differs, so it doesn't fold either

      to_roles!

      lineup = production.roles.production_roles.reload
      expect(lineup.map { |r| [ r.name, r.quantity, r.category ] }).to eq([
        [ "Dancer", 1, "performing" ], [ "Solo", 1, "performing" ], [ "Dancer (2)", 2, "performing" ],
        [ "Dancer (3)", 1, "technical" ], [ "Host", 1, "performing" ]
      ])
      expect(lineup.map(&:position)).to eq([ 0, 1, 2, 3, 4 ])
      expect(lineup).to all(be_valid)
      expect(cast_of(show).size).to eq(6)
    end

    it "keeps acts with different eligibility apart" do
      to_acts!
      second = production.roles.production_roles.reload.to_a[1]
      second.update_columns(restricted: true)
      second.role_eligibilities.create!(member: dancers[1])

      to_roles!

      expect(production.roles.production_roles.reload.map { |r| [ r.name, r.quantity, r.restricted? ] })
        .to eq([ [ "Dancer", 1, false ], [ "Dancer (2)", 1, true ], [ "Dancer (3)", 3, false ], [ "Host", 1, false ] ])
    end

    it "deletes breaks — they aren't roles" do
      to_acts!
      production.roles.create!(name: "Intermission", category: "break", position: 2)

      summary = to_roles!

      expect(summary.breaks_removed).to eq(1)
      expect(production.roles.production_roles.reload.map(&:name)).to eq(%w[Dancer Host])
      expect(production.roles.production_roles.reload).to all(be_valid)
    end

    it "is idempotent — running it again changes nothing" do
      to_acts!
      to_roles!
      before_roles = production.roles.production_roles.reload.map { |r| [ r.id, r.name, r.position, r.quantity ] }
      before_cast = cast_of(show)

      summary = described_class.to_roles!(production)

      expect(summary).not_to be_changed
      expect(production.roles.production_roles.reload.map { |r| [ r.id, r.name, r.position, r.quantity ] }).to eq(before_roles)
      expect(cast_of(show)).to eq(before_cast)
    end

    it "merges the custom lineup of a show that inherits the mode, gives an act-pinned show its own act lineup, and leaves the rest" do
      to_acts!
      inheriting = create(:show, production: production, use_custom_roles: true, date_and_time: 5.days.from_now)
      duo1 = create(:role, production: production, show: inheriting, name: "Duo", position: 0)
      duo2 = create(:role, production: production, show: inheriting, name: "Duo", position: 1)
      cast!(inheriting, duo1, dancers[0], 1)
      cast!(inheriting, duo2, dancers[1], 1)
      pinned_acts = create(:show, production: production, casting_mode: "act_based", date_and_time: 6.days.from_now)
      cast!(pinned_acts, production.roles.production_roles.reload.to_a[2], dancers[2], 1)
      pinned_custom_acts = create(:show, production: production, casting_mode: "act_based", use_custom_roles: true, date_and_time: 8.days.from_now)
      create(:role, production: production, show: pinned_custom_acts, name: "Magic", position: 0)
      create(:role, production: production, show: pinned_custom_acts, name: "Magic", position: 1)

      summary = to_roles!

      expect(inheriting.custom_roles.reload.map { |r| [ r.id, r.name, r.quantity ] }).to eq([ [ duo1.id, "Duo", 2 ] ])
      expect(cast_of(inheriting)).to contain_exactly([ dancers[0].name, "Duo", 0, 1 ], [ dancers[1].name, "Duo", 0, 2 ])
      # the act-pinned show cast from the production's acts: it keeps them, as its own lineup
      expect(summary.lineups_copied).to eq(1)
      pinned_acts.reload
      expect(pinned_acts).to be_use_custom_roles
      expect(pinned_acts.custom_roles.map(&:name)).to eq(%w[Dancer Dancer Dancer Dancer Dancer Host])
      expect(cast_of(pinned_acts)).to eq([ [ dancers[2].name, "Dancer", 2, 1 ] ])
      # a pinned show's own act lineup isn't touched
      expect(pinned_custom_acts.custom_roles.reload.map(&:name)).to eq(%w[Magic Magic])
    end

    it "refuses to run on a production that isn't role-based" do
      production.update!(casting_mode: "act_based")
      expect { described_class.to_roles!(production) }.to raise_error(ArgumentError)
    end
  end

  describe "show roles (standing) through a round trip" do
    let!(:kittens) { create(:role, production: production, name: "Stage Kitten", category: "technical", quantity: 2, position: 2) }
    let(:kitten_people) { (1..2).map { |i| create(:person, name: "Kitten #{i}").tap { |p| org.people << p } } }

    before { kitten_people.each_with_index { |p, i| cast!(show, kittens, p, i + 1) } }

    def to_acts!
      production.update!(casting_mode: "act_based")
      described_class.to_acts!(production)
    end

    def to_roles!
      production.update!(casting_mode: "role_based")
      described_class.to_roles!(production)
    end

    it "keeps a technical role as one show role with its slots instead of splitting it into acts" do
      summary = to_acts!

      kittens.reload
      expect(summary.roles_kept_standing).to eq(1)
      expect(kittens).to be_standing
      expect(kittens.category).to eq("technical")
      expect(kittens.quantity).to eq(2)
      expect(kittens).not_to be_act
      expect(production.roles.production_roles.where(name: "Stage Kitten").count).to eq(1)
      expect(kittens.show_person_role_assignments.count).to eq(2)
      # The dancers still split into acts.
      expect(production.roles.production_roles.where(name: "Dancer").count).to eq(5)
    end

    it "never splits a show role, however many slots it holds" do
      production.update!(casting_mode: "act_based")
      ushers = create(:role, production: production, name: "Usher", standing: true, quantity: 3, position: 3)
      described_class.to_acts!(production)
      expect(production.roles.production_roles.where(name: "Usher").count).to eq(1)
      expect(ushers.reload.quantity).to eq(3)
    end

    it "clears the flag on the way back, so the technical role comes back exactly as it was" do
      to_acts!
      summary = to_roles!

      kittens.reload
      expect(summary.standing_cleared).to eq(1)
      expect(kittens).not_to be_standing
      expect(kittens.category).to eq("technical")
      expect(kittens.quantity).to eq(2)
      expect(kittens.show_person_role_assignments.count).to eq(2)
      expect(production.roles.production_roles.map(&:name)).to eq([ "Dancer", "Host", "Stage Kitten" ])
    end

    it "keeps a show role apart from a same-named act when folding" do
      production.update!(casting_mode: "act_based")
      # A show role's name is unique, an act's isn't — so the act comes second.
      a = create(:role, production: production, name: "MC", standing: true, position: 20)
      b = create(:role, production: production, name: "MC", position: 21)
      runs = described_class.mergeable_runs([ a, b ])
      expect(runs.map(&:size)).to eq([ 1, 1 ])
    end

    it "gives one show its own copy when only a technical role needs to become a show role" do
      dancer.update!(quantity: 1)
      show.update!(casting_mode: "act_based")
      summary = described_class.to_acts_for_show!(show)

      expect(summary.lineups_copied).to eq(1)
      expect(show.reload.use_custom_roles?).to be(true)
      expect(show.custom_roles.find_by(name: "Stage Kitten")).to be_standing
      expect(kittens.reload).not_to be_standing
    end
  end

  describe ".mergeable_runs / .unique_name (the role shape of an act lineup)" do
    it "groups adjacent look-alike acts, skips breaks, and keeps different acts apart" do
      production.update!(casting_mode: "act_based")
      names = [ [ "Magic", "performing" ], [ "Magic", "performing" ], [ "Intermission", "break" ],
                [ "Magic", "performing" ], [ "Magic", "technical" ], [ "Clown", "performing" ] ]
      roles = names.each_with_index.map { |(n, c), i| create(:role, production: production, name: n, category: c, position: 10 + i) }

      runs = described_class.mergeable_runs(roles)

      expect(runs.map { |run| run.map(&:name) }).to eq([ %w[Magic Magic Magic], [ "Magic" ], [ "Clown" ] ])
    end

    it "hands out the first free suffixed name" do
      taken = Set.new
      expect(described_class.unique_name("Magic", taken)).to eq("Magic")
      expect(described_class.unique_name("Magic", taken)).to eq("Magic (2)")
      expect(described_class.unique_name("Magic", taken)).to eq("Magic (3)")
      expect(described_class.unique_name("Clown", taken)).to eq("Clown")
    end
  end

  describe ".to_roles_for_show! (one show going back to roles)" do
    let(:variety_night) { create(:show, production: production, casting_mode: "act_based", use_custom_roles: true, date_and_time: 5.days.from_now) }

    before do
      %w[Magic Magic Intermission Magic].each_with_index do |name, i|
        create(:role, production: production, show: variety_night, name: name, position: i,
                      category: name == "Intermission" ? "break" : "performing")
      end
      cast!(variety_night, variety_night.custom_roles.first, dancers[0], 1)
      cast!(variety_night, variety_night.custom_roles.reload.to_a[1], dancers[1], 1)
    end

    it "folds its own lineup back into roles, drops the break, and later role edits validate" do
      variety_night.update!(casting_mode: nil)
      summary = described_class.to_roles_for_show!(variety_night)

      # the break goes first (it isn't a role), so the three Magic acts are one run
      expect(summary.breaks_removed).to eq(1)
      lineup = variety_night.custom_roles.reload
      expect(lineup.map { |r| [ r.name, r.quantity, r.category, r.position ] }).to eq([ [ "Magic", 3, "performing", 0 ] ])
      expect(lineup).to all(be_valid)
      expect(cast_of(variety_night)).to contain_exactly([ dancers[0].name, "Magic", 0, 1 ], [ dancers[1].name, "Magic", 0, 2 ])
      lineup.first.name = "Closer"
      expect(lineup.first.save).to be(true)
      # a role-based show has no place for breaks
      expect(variety_night.custom_roles.breaks).to be_empty
    end

    it "suffixes a repeated name that isn't in a row" do
      variety_night.custom_roles.reload.to_a[1].update_columns(name: "Clown")
      variety_night.update!(casting_mode: nil)

      described_class.to_roles_for_show!(variety_night)

      expect(variety_night.custom_roles.reload.map { |r| [ r.name, r.quantity ] }).to eq([ [ "Magic", 1 ], [ "Clown", 1 ], [ "Magic (2)", 1 ] ])
      expect(variety_night.custom_roles.reload).to all(be_valid)
    end

    it "gives a show casting from an act-based production's acts a role-shaped copy, cast kept" do
      production.update!(casting_mode: "act_based")
      described_class.to_acts!(production)
      night = create(:show, production: production, date_and_time: 9.days.from_now)
      acts = production.roles.production_roles.reload.to_a
      cast!(night, acts[0], dancers[0], 1)
      cast!(night, acts[2], dancers[2], 1)
      cast!(night, host, mc, 1)
      night.update!(casting_mode: "role_based")

      summary = described_class.to_roles_for_show!(night)

      expect(summary.lineups_copied).to eq(1)
      night.reload
      expect(night).to be_use_custom_roles
      expect(night.custom_roles.map { |r| [ r.name, r.quantity ] }).to eq([ [ "Dancer", 5 ], [ "Host", 1 ] ])
      expect(night.custom_roles).to all(be_valid)
      expect(cast_of(night)).to contain_exactly([ dancers[0].name, "Dancer", 0, 1 ], [ dancers[2].name, "Dancer", 0, 2 ], [ "The MC", "Host", 1, 1 ])
      # the production's acts are untouched
      expect(production.roles.production_roles.reload.map(&:name)).to eq(%w[Dancer Dancer Dancer Dancer Dancer Host])
    end

    it "leaves a show sharing a role-based production's roles alone" do
      night = create(:show, production: production, casting_mode: "act_based", date_and_time: 9.days.from_now)
      night.update!(casting_mode: nil)

      summary = described_class.to_roles_for_show!(night)

      expect(summary).not_to be_changed
      expect(night.reload).not_to be_use_custom_roles
    end

    it "round-trips one show: roles → acts → roles restores its lineup with everyone in a slot" do
      show.update!(casting_mode: "act_based")
      described_class.to_acts_for_show!(show)
      expect(show.custom_roles.reload.count).to eq(6)

      show.update!(casting_mode: nil)
      described_class.to_roles_for_show!(show)

      expect(show.custom_roles.reload.map { |r| [ r.name, r.quantity ] }).to eq([ [ "Dancer", 5 ], [ "Host", 1 ] ])
      cast = show.show_person_role_assignments.reload
      expect(cast.size).to eq(6)
      expect(cast.select { |a| a.role.name == "Dancer" }.map(&:position)).to contain_exactly(1, 2, 3, 4, 5)
    end
  end
end
