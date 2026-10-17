# frozen_string_literal: true

require "rails_helper"

# A show's services on Scheduling (after-V1 #6): each one it needs with who's
# on it, Role Call flagging the ones nobody's on, the per-show changes from its
# panel, and "Staff it" offering the service's roles plus "Someone else".
RSpec.describe "Show services on Scheduling", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner, alert_uncovered_show_roles: true) }
  let(:production) { create(:production, organization: org, name: "Halloween o' Weens") }
  # Next week, so the show is always still to come (the summary skips past ones).
  let(:week_start) { Date.current.next_week.beginning_of_week }
  let!(:show) { create(:show, production: production, date_and_time: (week_start + 2).in_time_zone.change(hour: 20), duration_minutes: 90) }

  let!(:booth_role) { create(:house_role, organization: org, name: "Booth Tech", role_type: :show_specific, include_in_role_call: false) }
  let!(:foh) { create(:house_role, organization: org, name: "Front of House", role_type: :house) }
  let!(:booth) { org.house_services.create!(name: "Booth Tech", position: 0).tap { |s| s.house_roles << booth_role } }
  let!(:tickets) { org.house_services.create!(name: "Ticket taking", position: 1).tap { |s| s.house_roles << foh } }
  let!(:projector) { org.house_services.create!(name: "Projector rental", position: 2) }

  def staff!(name, *roles)
    person = create(:person, name: name)
    org.people << person
    member = create(:organization_staff_member, organization: org, person: person)
    roles.each { |r| create(:staff_role_qualification, organization_staff_member: member, house_role: r) }
    person
  end

  def page_html
    get manage_staffing_scheduling_path(week_start: week_start.to_s)
    response.body.gsub(/\s+/, " ")
  end

  before do
    create(:organization_role, :manager, user: owner, organization: org)
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
    production.production_service_needs.create!(house_service: booth)
    production.production_service_needs.create!(house_service: tickets)
    production.production_service_needs.create!(house_service: projector)
  end

  it "lists what the show needs, counts an evening shift that overlaps it, and flags the rest" do
    archie = staff!("Archie Maggio", foh)
    evening = create(:shift, organization: org, house_role: foh, starts_at: show.date_and_time - 1.hour, ends_at: show.ends_at + 1.hour)
    create(:shift_assignment, shift: evening, person: archie)

    html = page_html
    expect(html).to include("What this show needs", "Ticket taking", "Archie Maggio", "needs Booth Tech",
                            edit_manage_production_path(production, tab: 8))
    expect(html).not_to include("needs Ticket taking") # Archie's on it
    expect(html).not_to include("Projector rental</p>") # equipment isn't staffed, so it isn't listed
    expect(html).to include(%(data-allowed-role-ids="[#{booth_role.id}]"), %(data-service-name="Booth Tech"))
  end

  it "drops a service for this show alone, puts it back, and adds one just for it" do
    patch manage_staffing_show_service_path(show, service_id: booth.id, needed: "0")
    expect(flash[:notice]).to eq("#{show.display_name} won't need Booth Tech.")
    expect(page_html).not_to include("needs Booth Tech")
    expect(page_html).to include("Not needed for this show", "Needs it again")

    patch manage_staffing_show_service_path(show, service_id: booth.id, needed: "1")
    expect(show.show_service_changes.reload).to be_empty
    expect(page_html).to include("needs Booth Tech")

    video_role = create(:house_role, organization: org, name: "Videographer", role_type: :show_specific)
    video = org.house_services.create!(name: "Videographer").tap { |s| s.house_roles << video_role }
    patch manage_staffing_show_service_path(show, needed: "1"), params: { service_id: video.id }
    expect(ShowServices.new([ show ]).for(show).map { |n| [ n.service.name, n.source ] }).to include([ "Videographer", :show ])
  end

  it "won't touch another organization's show" do
    elsewhere = create(:show, production: create(:production))
    patch manage_staffing_show_service_path(elsewhere, service_id: booth.id, needed: "0")
    expect(flash[:alert]).to eq("We couldn't find that show.")
    expect(ShowServiceChange.count).to eq(0)
  end

  it "puts someone else on a shift when picked as someone else, and only then" do
    sam = staff!("Sam Staff") # on staff, on no role
    params = { shift: { house_role_id: foh.id, starts_at: "#{show.date_and_time.to_date}T19:00", ends_at: "#{show.date_and_time.to_date}T21:30",
                        source_type: "Show", source_id: show.id, required_count: 1, coverage_mode: "needs_assignment" }, person_id: sam.id }

    post manage_create_staffing_shift_path, params: params
    expect(flash[:notice]).to include("not on staff or not qualified")
    expect(ShiftAssignment.count).to eq(0)

    Shift.destroy_all
    post manage_create_staffing_shift_path, params: params.merge(anyone: "1")
    expect(flash[:notice]).to include("Assigned Sam Staff.")
    expect(page_html).not_to include("needs Ticket taking")

    stranger = create(:person, name: "Not On Staff")
    Shift.destroy_all
    post manage_create_staffing_shift_path, params: params.merge(anyone: "1", person_id: stranger.id)
    expect(ShiftAssignment.count).to eq(0)
  end

  it "sums up what's still to staff this week, and adds the missing shifts in one go" do
    html = page_html
    expect(html).to include("Still to staff this week", "2 services on 1 show", "Booth Tech on 1 show and Ticket taking on 1 show", "Add the 2 shifts")

    post manage_add_staffing_service_shifts_path(week_start: week_start.to_s)
    expect(flash[:notice]).to eq("Added 2 shifts. Now pick who works them.")
    expect(Shift.where(source: show).map { |s| [ s.house_role.name, s.starts_at, s.ends_at, s.assigned_count ] })
      .to contain_exactly([ "Booth Tech", show.date_and_time, show.ends_at, 0 ], [ "Front of House", show.date_and_time, show.ends_at, 0 ])

    # Shifts exist now, so nothing more to add, but they still need people.
    expect(page_html).to include("Their shifts are added: pick who works them.")
    expect(page_html).not_to include("Add the 2 shifts")
    post manage_add_staffing_service_shifts_path(week_start: week_start.to_s)
    expect(flash[:notice]).to eq("Every service already has its shift.")
  end

  it "keeps the summary off with Role Call off" do
    org.update!(alert_uncovered_show_roles: false)
    expect(page_html).not_to include("Still to staff this week")
    expect(page_html).to include("What this show needs")
  end

  it "names a service once when an every-show role shares its name, and Role Call doesn't repeat it" do
    booth_role.update!(include_in_role_call: true)
    expect(page_html).to include("needs Booth Tech")
    expect(page_html).not_to include("Booth Tech and Booth Tech")
    # The service row says Booth Tech; with no other every-show role, there's
    # no Role Call block to say it again.
    expect(page_html).not_to include("The roles every show needs")

    # An every-show role no service carries still gets its Role Call row.
    create(:house_role, organization: org, name: "House Manager", role_type: :show_specific, include_in_role_call: true)
    html = page_html
    expect(html).to include("The roles every show needs", "House Manager", "Not covered yet")
    expect(html.scan(%r{<p class="text-sm font-medium text-gray-900">Booth Tech</p>})).to be_empty
  end

  it "says nothing about services without Pro" do
    org.update!(comped_indefinitely: false)
    get manage_staffing_scheduling_path(week_start: week_start.to_s)
    expect(response.body).not_to include("What this show needs")
  end
end
