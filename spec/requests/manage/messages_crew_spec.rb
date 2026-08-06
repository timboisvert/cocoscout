# frozen_string_literal: true

require "rails_helper"

# Messaging a show's crew, not just its cast. The compose modal reads
# production_data; these cover what that payload offers and that a cast+crew
# send resolves to one de-duplicated person list.
RSpec.describe "Messaging a show's cast and crew", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org) }
  let!(:show) { create(:show, production: production, date_and_time: 2.days.from_now.change(hour: 20)) }
  let(:role) { create(:house_role, organization: org, name: "Booth Tech") }

  # Messages only reach people with accounts (MessageService#create_message
  # filters on it), so both need users for the send assertion to mean anything.
  let(:performer) { create(:person, name: "Ada Actor", user: create(:user)) }
  let(:tech) { create(:person, name: "Tess Tech", user: create(:user)) }

  before do
    org.people << performer unless org.people.exists?(performer.id)
    create(:show_person_role_assignment, show: show, assignable: performer)
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
  end

  def staff_the_show!(person, shift_show: false, house_role: role)
    shift = create(:shift, organization: org, house_role: house_role,
                           source: shift_show ? nil : show,
                           starts_at: show.date_and_time - 1.hour, ends_at: show.date_and_time + 2.hours)
    ShiftShow.create!(shift: shift, show: show) if shift_show
    create(:shift_assignment, shift: shift, person: person)
    shift
  end

  it "reports the crew alongside the cast" do
    staff_the_show!(tech)

    get production_data_manage_messages_path(production_id: production.id)
    data = JSON.parse(response.body)
    show_data = data["shows"].find { |s| s["id"] == show.id }

    expect(show_data["cast_person_ids"]).to eq([ performer.id ])
    expect(show_data["crew_count"]).to eq(1)
    expect(show_data["crew"].first["role"]).to eq("Booth Tech")
    expect(show_data["crew"].first["people"].first["name"]).to eq("Tess Tech")
  end

  it "finds crew on a merged shift, which attaches by shift_shows not source" do
    staff_the_show!(tech, shift_show: true)

    get production_data_manage_messages_path(production_id: production.id)
    show_data = JSON.parse(response.body)["shows"].find { |s| s["id"] == show.id }

    expect(show_data["crew_count"]).to eq(1)
  end

  it "leaves an unassigned shift out — there's nobody to message" do
    create(:shift, organization: org, house_role: role, source: show,
                   starts_at: show.date_and_time, ends_at: show.date_and_time + 2.hours)

    get production_data_manage_messages_path(production_id: production.id)
    show_data = JSON.parse(response.body)["shows"].find { |s| s["id"] == show.id }

    expect(show_data["crew"]).to be_empty
  end

  it "sends to cast and crew as one list, without duplicating anyone on both" do
    org.people << tech unless org.people.exists?(tech.id)
    staff_the_show!(tech)
    # Ada both performs and works the door.
    staff_the_show!(performer, house_role: create(:house_role, organization: org, name: "Door"))

    expect {
      post manage_messages_path, params: {
        recipient_type: "batch", person_ids: [ performer.id, tech.id, performer.id ],
        subject: "Call time moved", body: "We start at 7."
      }
    }.to change(Message, :count).by_at_least(1)

    recipients = Message.order(:created_at).last.recipient_people.map(&:id)
    expect(recipients).to contain_exactly(performer.id, tech.id)
  end
end
