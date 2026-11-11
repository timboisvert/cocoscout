# frozen_string_literal: true

require "rails_helper"

# Archiving takes a location out of the list and the pickers and changes
# nothing that already points at it.
RSpec.describe Location, "archiving", type: :model do
  let(:organization) { create(:organization) }
  let!(:home) { create(:location, organization: organization, name: "Main Stage") }
  let!(:library) { create(:location, organization: organization, name: "Merlo Public Library") }

  it "leaves active and joins archived" do
    library.archive!

    expect(library.reload).to be_archived
    expect(organization.locations.active).to contain_exactly(home)
    expect(organization.locations.archived).to contain_exactly(library)
  end

  it "keeps its shows and rooms" do
    room = library.location_spaces.create!(name: "Reading Room")
    show = create(:show, production: create(:production, organization: organization), location: library, location_space: room)

    library.archive!

    expect(show.reload.location).to eq(library)
    expect(show.location_space).to eq(room)
    expect(library.location_spaces).to contain_exactly(room)
  end

  it "passes the default to the oldest other location in use" do
    expect(home.reload).to be_default

    home.archive!

    expect(home.reload).not_to be_default
    expect(library.reload).to be_default
  end

  it "never leaves an archived location as the default" do
    library.archive!
    library.update!(default: true)

    expect(library.reload).not_to be_default
    expect(home.reload).to be_default
  end

  it "restores, and takes the default only when nobody has it" do
    library.archive!
    library.restore!
    expect(library.reload).not_to be_archived
    expect(library).not_to be_default

    home.archive!
    library.archive!
    expect(organization.locations.where(default: true)).to be_empty
    home.restore!
    expect(home.reload).to be_default
  end

  it "offers pickers the locations in use plus the ones a record already has" do
    library.archive!

    expect(organization.locations.pickable).to contain_exactly(home)
    expect(organization.locations.pickable(nil)).to contain_exactly(home)
    expect(organization.locations.pickable(library.id)).to contain_exactly(home, library)
    expect(organization.locations.pickable([ library.id ], [])).to contain_exactly(home, library)
  end

  it "finds the location ids named in a contract's draft data" do
    data = { "booking_rules" => { "rules" => [ { "location_id" => "4" } ] }, "bookings" => [ { "location_id" => 9 }, { "location_id" => "" } ] }

    expect(described_class.ids_named_in(data)).to contain_exactly(4, 9)
  end
end
