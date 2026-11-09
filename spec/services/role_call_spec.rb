# frozen_string_literal: true

require "rails_helper"

# What Role Call asks of a show: its services, then the every-show roles its
# services don't carry. A contract production's needs come from its contract
# (Tim, 2026-11-08), so a role one of the organization's services carries is
# asked of a contract show only when its services include that service.
RSpec.describe RoleCall do
  let(:org) { create(:organization, :pro) }
  let!(:booth_role) { create(:house_role, organization: org, name: "Booth Tech", role_type: :show_specific, include_in_role_call: true) }
  let!(:manager_role) { create(:house_role, organization: org, name: "House Manager", role_type: :show_specific, include_in_role_call: true) }
  let!(:booth) { org.house_services.create!(name: "Booth Tech").tap { |s| s.house_roles << booth_role } }
  let(:ours) { create(:production, organization: org, name: "Laugh-Along, Live!") }
  let(:theirs) { create(:production, organization: org, production_type: "third_party", name: "Nuns4Fun") }
  let(:our_show) { create(:show, production: ours, date_and_time: 5.days.from_now.change(hour: 20)) }
  let(:their_show) { create(:show, production: theirs, date_and_time: 5.days.from_now.change(hour: 21)) }

  def role_call(services: true) = described_class.new(organization: org, shows: [ our_show, their_show ], services: services)
  def asked(show, **opts) = role_call(**opts).roles(show).map(&:name)
  def needed(show) = role_call.needs(show).select(&:needed?).map { |need| need.service.name }

  it "asks our own show for every every-show role, and a contract show only for the ones no service carries" do
    expect(asked(our_show)).to eq([ "Booth Tech", "House Manager" ])
    expect(asked(their_show)).to eq([ "House Manager" ])
    expect(needed(their_show)).to be_empty
  end

  it "asks a contract show for the service once its contract includes it" do
    create(:contract, :active, organization: org, production: theirs, draft_data: { "services" => [ { "name" => "Booth Tech", "service_id" => booth.id } ] })

    expect(needed(their_show)).to eq([ "Booth Tech" ])
    expect(asked(their_show)).to eq([ "House Manager" ]) # the service's line says Booth Tech
  end

  it "leaves a role its service carries to the service on our own show too, and puts it back when the show drops the service" do
    ours.production_service_needs.create!(house_service: booth)
    expect(needed(our_show)).to eq([ "Booth Tech" ])
    expect(asked(our_show)).to eq([ "House Manager" ])

    ShowServices.change!(our_show, booth, needed: false)
    expect(needed(our_show)).to be_empty
    expect(asked(our_show)).to eq([ "Booth Tech", "House Manager" ])
  end

  it "asks every show for every role when services aren't on" do
    expect(asked(their_show, services: false)).to eq([ "Booth Tech", "House Manager" ])
    expect(role_call(services: false).needs(their_show)).to be_empty
  end

  it "keeps a venue's role to shows at that venue" do
    manager_role.update!(location: create(:location, organization: org))
    expect(asked(our_show)).to eq([ "Booth Tech" ])
  end
end
