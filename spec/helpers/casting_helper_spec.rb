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
end
