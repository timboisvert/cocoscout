# frozen_string_literal: true

require "rails_helper"

# The timekeeping panel asks you to verify hours for every past shift you were
# assigned to. It used to ask about shifts you had told them you couldn't make —
# which is how "I can't make it" could turn into payable time.
RSpec.describe "My::Shifts hours after a decline", type: :request do
  let(:password) { "Password123!" }
  let(:user) { create(:user, password: password) }
  let!(:person) { create(:person, user: user, name: "Quinn") }
  let!(:org) { create(:organization, :pro) }
  let!(:membership) { create(:organization_staff_member, organization: org, person: person) }
  let!(:role) { create(:house_role, organization: org, name: "Bar") }

  let(:worked_at) { 3.days.ago.change(hour: 18) }
  let!(:shift) do
    create(:shift, organization: org, house_role: role,
                   starts_at: worked_at, ends_at: worked_at + 4.hours)
  end
  let!(:assignment) { shift.shift_assignments.create!(person: person, position: 1) }

  before do
    org.people << person unless org.people.include?(person)
    # Only finalized weeks reach the panel at all.
    StaffingFinalization.create!(organization: org, week_start: worked_at.to_date.beginning_of_week,
                                 finalized_at: Time.current)
    post handle_signin_path, params: { email_address: user.email_address, password: password }
  end

  it "asks you to verify a shift you actually worked" do
    get my_shifts_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Verify the hours you worked")
  end

  it "stops asking once you've said you couldn't make it" do
    assignment.decline!(reason: "Sick")

    get my_shifts_path

    expect(response.body).not_to include("Verify the hours you worked")
  end

  it "asks again if you come back on" do
    assignment.decline!
    assignment.undo_decline!

    get my_shifts_path

    expect(response.body).to include("Verify the hours you worked")
  end
end
