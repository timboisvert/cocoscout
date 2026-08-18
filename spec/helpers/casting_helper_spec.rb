require "rails_helper"

RSpec.describe CastingHelper, type: :helper do
  # Lightweight stand-ins; the helper only touches #position and #quantity
  Assignment = Struct.new(:position, :name)
  FakeRole = Struct.new(:quantity)

  def names_in_slots(role, assignments)
    slots = helper.cast_assignments_by_slot(role, assignments)
    total = helper.cast_total_slots(role, slots)
    (1..total).map { |i| slots[i]&.name }
  end

  it "places exact positions in their slots" do
    role = FakeRole.new(3)
    assignments = [ Assignment.new(2, "B"), Assignment.new(1, "A"), Assignment.new(3, "C") ]
    expect(names_in_slots(role, assignments)).to eq(%w[A B C])
  end

  it "fills legacy nil/zero positions into free slots" do
    role = FakeRole.new(3)
    assignments = [ Assignment.new(1, "Matt"), Assignment.new(nil, "Amanda"), Assignment.new(3, "Kendall") ]
    expect(names_in_slots(role, assignments)).to eq(%w[Matt Amanda Kendall])
  end

  it "never drops an assignment with a duplicate position" do
    role = FakeRole.new(3)
    assignments = [ Assignment.new(1, "Matt"), Assignment.new(1, "Amanda"), Assignment.new(2, "Kendall") ]
    expect(names_in_slots(role, assignments)).to contain_exactly("Matt", "Amanda", "Kendall")
  end

  it "never drops an assignment with an out-of-range position" do
    role = FakeRole.new(2)
    assignments = [ Assignment.new(5, "A"), Assignment.new(1, "B") ]
    expect(names_in_slots(role, assignments)).to contain_exactly("A", "B")
  end

  it "extends past quantity rather than hiding overfull assignments" do
    role = FakeRole.new(1)
    assignments = [ Assignment.new(1, "A"), Assignment.new(0, "B") ]
    slots = helper.cast_assignments_by_slot(role, assignments)
    expect(helper.cast_total_slots(role, slots)).to eq(2)
    expect(names_in_slots(role, assignments)).to eq(%w[A B])
  end

  it "shows empty slots for unfilled quantity" do
    role = FakeRole.new(3)
    assignments = [ Assignment.new(1, "A") ]
    expect(names_in_slots(role, assignments)).to eq([ "A", nil, nil ])
  end

  it "handles a role with nil quantity" do
    role = FakeRole.new(nil)
    expect(names_in_slots(role, [ Assignment.new(nil, "A") ])).to eq(%w[A])
    expect(names_in_slots(role, [])).to eq([ nil ])
  end

  describe "#act_assignment_labels" do
    let(:org) { create(:organization) }
    let(:production) { create(:production, organization: org, casting_mode: "act_based") }
    let(:show) { create(:show, production: production) }
    # Lineup: Magic, Variety, — Intermission —, Magic, Clown (acts 1, 2, 3, 4)
    let!(:magic_one) { create(:role, production: production, name: "Magic", position: 0) }
    let!(:variety) { create(:role, production: production, name: "Variety", position: 1) }
    let!(:intermission) { create(:role, production: production, name: "Intermission", category: "break", position: 2) }
    let!(:magic_two) { create(:role, production: production, name: "Magic", position: 3) }
    let!(:clown) { create(:role, production: production, name: "Clown", position: 4) }
    let(:performer) { create(:person) }

    def assign(*roles)
      roles.map { |r| create(:show_person_role_assignment, show: show, role: r, assignable: performer) }
    end

    it "names a single act with its number" do
      expect(helper.act_assignment_labels(assign(magic_two), show: show)).to eq([ "Magic (Act 3)" ])
    end

    it "groups same-named acts and lists their numbers in running order" do
      assignments = assign(magic_two, clown, magic_one)
      expect(helper.act_assignment_labels(assignments, show: show))
        .to eq([ "2 acts as Magic (Acts 1 and 3)", "Clown (Act 4)" ])
    end

    it "accepts roles as well as assignments and takes precomputed numbers" do
      numbers = helper.lineup_numbers(show.available_roles.to_a, show: show)
      expect(helper.act_assignment_labels([ variety, magic_one ], show: show, numbers: numbers))
        .to eq([ "Magic (Act 1)", "Variety (Act 2)" ])
    end

    it "never lists a break and returns nothing for no assignments" do
      expect(helper.act_assignment_labels([ intermission ], show: show)).to eq([])
      expect(helper.act_assignment_labels([], show: show)).to eq([])
    end

    it "keeps plain, distinct role names on a role-based show" do
      production.update!(casting_mode: "role_based")
      assignments = assign(magic_one, clown, magic_two)
      expect(helper.act_assignment_labels(assignments, show: show.reload)).to eq([ "Magic", "Clown" ])
    end

    it "picks the word that reads before each label" do
      expect(helper.cast_as_word("Magic (Act 3)")).to eq("as")
      expect(helper.cast_as_word("Host")).to eq("as")
      expect(helper.cast_as_word("2 acts as Magic (Acts 1 and 3)")).to eq("in")
    end
  end
end
