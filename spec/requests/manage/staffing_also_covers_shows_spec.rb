# frozen_string_literal: true

require "rails_helper"

# One bartender works a three-show evening and is also on tech — but only for
# the 9pm show. Before, an "also covers" role applied to every show on the shift,
# so Role Call would claim tech was covered all night. Now the role can name its
# shows, and every path that reshapes a shift (edit, merge, split) keeps that.
RSpec.describe "Manage::Staffing 'also covers' scoped to shows", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner, alert_uncovered_show_roles: true) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:location) { create(:location, organization: org) }
  let!(:production) { create(:production, organization: org, name: "Late Night") }

  let!(:bar) { create(:house_role, organization: org, name: "Bar") }
  let!(:tech) do
    create(:house_role, organization: org, name: "Tech", role_type: :show_specific, include_in_role_call: true)
  end

  # A fixed Wednesday, so the rendered week never depends on today.
  let(:evening) { Time.zone.local(2026, 9, 16, 0, 0) }
  let!(:early) { create(:show, production: production, location: location, date_and_time: evening.change(hour: 18), duration_minutes: 60) }
  let!(:middle) { create(:show, production: production, location: location, date_and_time: evening.change(hour: 21), duration_minutes: 60) }
  let!(:late) { create(:show, production: production, location: location, date_and_time: evening.change(hour: 23), duration_minutes: 45) }

  let!(:bartender) { create(:person, name: "Quinn") }

  let!(:shift) do
    create(:shift, organization: org, house_role: bar, source: early,
                   starts_at: evening.change(hour: 17), ends_at: evening.change(hour: 23, min: 59)).tap do |s|
      s.shows = [ middle, late ]
      s.shift_assignments.create!(person: bartender, position: 1)
    end
  end

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  def scheduling!
    get manage_staffing_scheduling_path(week_start: evening.to_date.beginning_of_week.to_s)
  end

  def edit!(role_ids:, scopes: {})
    patch manage_update_staffing_shift_path(shift), params: {
      shift: {
        starts_at: shift.starts_at.strftime("%Y-%m-%dT%H:%M"),
        ends_at: shift.ends_at.strftime("%Y-%m-%dT%H:%M"),
        additional_role_ids: [ "" ] + role_ids.map(&:to_s),
        additional_role_show_ids: scopes.transform_keys(&:to_s).transform_values { |ids| [ "" ] + ids.map(&:to_s) }
      }
    }
  end

  describe "Role Call" do
    # The amber chip renders more than once per show (the card and its panel),
    # so count it against the all-flagged baseline rather than as an absolute.
    def needs_tech_count
      scheduling!
      response.body.scan("needs Tech").size
    end

    it "flags every show when nobody is on tech" do
      baseline = needs_tech_count

      expect(response.body).to include(production.name)
      expect(baseline).to be_positive
      expect(baseline % 3).to eq(0)
    end

    it "covers every show when tech isn't scoped" do
      shift.assign_additional_roles!([ tech.id ])

      expect(needs_tech_count).to eq(0)
    end

    it "covers only the show tech was scoped to" do
      baseline = needs_tech_count
      shift.assign_additional_roles!([ tech.id ], tech.id => [ middle.id ])

      # Two of the three shows still need tech.
      expect(needs_tech_count).to eq(baseline * 2 / 3)
    end
  end

  describe "the edit modal" do
    it "saves a role scoped to one show" do
      edit!(role_ids: [ tech.id ], scopes: { tech.id => [ middle.id ] })

      expect(shift.reload.additional_role_scopes).to eq(tech.id => [ middle.id ])
    end

    it "saves a role with every chip left ticked as covering every show" do
      edit!(role_ids: [ tech.id ], scopes: { tech.id => [ early.id, middle.id, late.id ] })

      expect(shift.reload.additional_role_scopes).to eq(tech.id => [])
    end

    it "saves an unscoped role when the modal didn't offer scoping" do
      edit!(role_ids: [ tech.id ])

      expect(shift.reload.additional_role_scopes).to eq(tech.id => [])
    end

    it "clears the set when every box is unticked" do
      shift.assign_additional_roles!([ tech.id ])

      edit!(role_ids: [])

      expect(shift.reload.additional_roles).to be_empty
    end

    it "hands the modal the covered shows and current scopes" do
      shift.assign_additional_roles!([ tech.id ], tech.id => [ middle.id ])

      scheduling!

      expect(response.body).to include("data-shift-covered-shows=")
      expect(response.body).to include("data-shift-additional-role-scopes=")
      # The card names the show the role is for.
      expect(response.body).to include("Tech (9:00 PM)")
    end

    it "won't take a role from another organization" do
      foreign = create(:house_role, organization: create(:organization, :pro), name: "Theirs")

      edit!(role_ids: [ foreign.id ])

      expect(shift.reload.additional_roles).to be_empty
    end
  end

  describe "splitting back into shows" do
    it "sends a scoped role to its own show's shift" do
      shift.assign_additional_roles!([ tech.id ], tech.id => [ late.id ])

      post manage_split_staffing_shift_path(shift), params: { by_show: "1" }

      late_shift = Shift.find_by(source: late, house_role: bar)
      expect(late_shift.additional_roles).to eq([ tech ])
      expect(shift.reload.additional_roles).to be_empty
    end

    it "keeps an every-show role on the first shift, as before" do
      shift.assign_additional_roles!([ tech.id ])

      post manage_split_staffing_shift_path(shift), params: { by_show: "1" }

      expect(shift.reload.additional_roles).to eq([ tech ])
      expect(Shift.find_by(source: late, house_role: bar).additional_roles).to be_empty
    end
  end

  describe "merging" do
    let!(:single) do
      create(:shift, organization: org, house_role: bar, source: early,
                     starts_at: evening.change(hour: 17), ends_at: evening.change(hour: 19))
    end
    let!(:other) do
      create(:shift, organization: org, house_role: bar, source: middle,
                     starts_at: evening.change(hour: 20), ends_at: evening.change(hour: 22))
    end

    before { shift.destroy! }

    it "pins each shift's extra roles to the shows that shift covered" do
      single.assign_additional_roles!([ tech.id ])

      post manage_merge_staffing_shift_path(single), params: { shift_ids: [ other.id ] }

      merged = single.reload
      expect(merged.covered_shows).to contain_exactly(early, middle)
      # Tech was only ever on the early show's shift — it doesn't spread to 9pm.
      expect(merged.additional_role_scopes).to eq(tech.id => [ early.id ])
    end

    it "keeps both shows when merging with the next shift" do
      single.update!(ends_at: other.starts_at)
      other.assign_additional_roles!([ tech.id ])

      post manage_merge_with_next_staffing_shift_path(single)

      merged = single.reload
      # This used to drop the next shift's show entirely.
      expect(merged.covered_shows).to contain_exactly(early, middle)
      expect(merged.additional_role_scopes).to eq(tech.id => [ middle.id ])
    end
  end
end
