# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261118193817_productions_say_whether_people_are_cast")

# The answer for productions that already exist is read from what they have
# (Tim, 2026-11-18), and no date's own casting switch is changed.
RSpec.describe ProductionsSayWhetherPeopleAreCast do
  def backfill!
    ActiveRecord::Migration.suppress_messages { described_class.new.backfill }
  end

  # As rows looked before the column existed: every production "yes", dates
  # with whatever switch they had.
  def production_with(dates: [], roles: 0, **attributes)
    production = create(:production, **attributes.except(:casting_setup_completed))
    dates.each { |casting| create(:show, production: production).update_columns(casting_enabled: casting) }
    roles.times { create(:role, production: production) }
    production.update_columns(casts_people: true, casting_setup_completed: attributes.fetch(:casting_setup_completed, false))
    production
  end

  it "says no only for a production whose every date has casting off and that has no roles" do
    all_off = production_with(dates: [ false, false ])
    some_on = production_with(dates: [ true, false ])
    off_with_roles = production_with(dates: [ false ], roles: 1)
    no_dates = production_with

    backfill!

    expect(all_off.reload.casts_people).to be(false)
    expect(some_on.reload.casts_people).to be(true)
    expect(off_with_roles.reload.casts_people).to be(true)
    expect(no_dates.reload.casts_people).to be(true)
  end

  it "changes no date's own switch" do
    production = production_with(dates: [ true, false ])
    before = production.shows.order(:id).pluck(:casting_enabled)

    backfill!
    expect(production.shows.order(:id).pluck(:casting_enabled)).to eq(before)
  end

  it "marks a production with roles, or with anyone cast, as set up" do
    with_roles = production_with(roles: 1)
    cast = production_with(dates: [ true ])
    create(:show_person_role_assignment, show: cast.shows.first, role: create(:role, production: cast, show: cast.shows.first))
    cast.update_columns(casting_setup_completed: false)
    bare = production_with(dates: [ true ])

    backfill!

    expect(with_roles.reload.casting_setup_completed).to be(true)
    expect(cast.reload.casting_setup_completed).to be(true)
    expect(bare.reload.casting_setup_completed).to be(false)
  end

  it "takes back 'set up' from an organization's first production, which was never asked" do
    organization = create(:organization, :pro)
    first = production_with(organization: organization, casting_setup_completed: true)
    first.update_columns(created_at: organization.created_at + 5.seconds)
    later = production_with(organization: organization, casting_setup_completed: true)
    later.update_columns(created_at: organization.created_at + 2.days)

    backfill!

    expect(first.reload.casting_setup_completed).to be(false)
    expect(later.reload.casting_setup_completed).to be(true)
  end
end
