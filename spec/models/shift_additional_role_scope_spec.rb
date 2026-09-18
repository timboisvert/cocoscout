# frozen_string_literal: true

require "rails_helper"

# An "also covers" role on a shift that spans several shows can name the shows
# it covers. NULL show_id still means every show, so the old meaning holds.
RSpec.describe "Shift extra roles scoped to shows", type: :model do
  let(:org) { create(:organization, :pro) }
  let(:production) { create(:production, organization: org) }
  let(:bar) { create(:house_role, organization: org, name: "Bar") }
  let(:tech) { create(:house_role, organization: org, name: "Tech", role_type: :show_specific) }
  let(:manager) { create(:house_role, organization: org, name: "Manager") }

  let(:evening) { Time.zone.local(2026, 10, 2, 0, 0) }
  let(:first_show)  { create(:show, production: production, date_and_time: evening.change(hour: 18)) }
  let(:second_show) { create(:show, production: production, date_and_time: evening.change(hour: 20)) }
  let(:third_show)  { create(:show, production: production, date_and_time: evening.change(hour: 22)) }

  # One bar shift across three shows, the way a merge leaves it.
  let(:shift) do
    create(:shift, organization: org, house_role: bar, source: first_show,
                   starts_at: evening.change(hour: 17), ends_at: evening.change(hour: 23, min: 59)).tap do |s|
      s.shows = [ second_show, third_show ]
    end
  end

  describe "#assign_additional_roles!" do
    it "stores an unscoped role as one row covering every show" do
      shift.assign_additional_roles!([ manager.id ])

      expect(shift.shift_additional_roles.map(&:show_id)).to eq([ nil ])
      expect(shift.additional_role_scopes).to eq(manager.id => [])
    end

    it "scopes a role to the shows picked" do
      shift.assign_additional_roles!([ tech.id ], tech.id => [ second_show.id ])

      expect(shift.shift_additional_roles.map(&:show_id)).to eq([ second_show.id ])
      expect(shift.additional_roles_for(second_show)).to eq([ tech ])
      expect(shift.additional_roles_for(first_show)).to be_empty
      expect(shift.additional_roles_for(third_show)).to be_empty
    end

    it "collapses back to every show when every show is picked" do
      shift.assign_additional_roles!([ tech.id ], tech.id => [ first_show.id, second_show.id, third_show.id ])

      expect(shift.shift_additional_roles.map(&:show_id)).to eq([ nil ])
    end

    it "drops a role whose shows were all unticked" do
      shift.assign_additional_roles!([ tech.id, manager.id ], tech.id => [])

      expect(shift.additional_roles).to eq([ manager ])
    end

    it "ignores shows the shift doesn't cover" do
      stranger = create(:show, production: production, date_and_time: evening.change(hour: 12))

      shift.assign_additional_roles!([ tech.id ], tech.id => [ stranger.id, second_show.id ])

      expect(shift.shift_additional_roles.map(&:show_id)).to eq([ second_show.id ])
    end

    it "never adds the shift's own primary role" do
      shift.assign_additional_roles!([ bar.id, manager.id ])

      expect(shift.additional_roles).to eq([ manager ])
    end

    it "lists a role once however many shows it's scoped to" do
      shift.assign_additional_roles!([ tech.id ], tech.id => [ first_show.id, third_show.id ])

      expect(shift.reload.additional_roles.to_a).to eq([ tech ])
      expect(Shift.includes(:additional_roles).find(shift.id).additional_roles.to_a).to eq([ tech ])
      expect(shift.role_label).to eq("Bar + Tech")
    end
  end

  describe "validation" do
    it "rejects a show the shift doesn't cover" do
      stranger = create(:show, production: production, date_and_time: evening.change(hour: 12))
      row = shift.shift_additional_roles.build(house_role: tech, show: stranger)

      expect(row).not_to be_valid
    end

    it "won't let a role be both everywhere and scoped" do
      shift.shift_additional_roles.create!(house_role: tech)
      row = shift.shift_additional_roles.build(house_role: tech, show: second_show)

      expect(row).not_to be_valid
    end
  end

  it "loses the scoped note when its show is deleted, instead of blocking the delete" do
    shift.assign_additional_roles!([ tech.id ], tech.id => [ third_show.id ])

    expect { third_show.destroy! }.not_to raise_error
    expect(ShiftAdditionalRole.where(shift: shift).count).to eq(0)
  end
end
