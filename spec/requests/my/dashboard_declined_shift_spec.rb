# frozen_string_literal: true

require "rails_helper"

# My Calendar shows the shifts you're on, in published weeks. One you said
# you can't make isn't one you're on.
RSpec.describe "My Calendar after a shift decline", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:password) { "Password123!" }
  let(:user) { create(:user, password: password) }
  let!(:person) { create(:person, user: user).tap { |p| user.update!(default_person: p) } }
  let!(:org) { create(:organization, :pro, name: "Stars & Garters") }
  let!(:role) { create(:house_role, organization: org, name: "Zamboni driver") }
  let(:shift_at) { Time.zone.local(2026, 11, 14, 19, 0) }
  let!(:shift) { create(:shift, organization: org, house_role: role, starts_at: shift_at, ends_at: shift_at + 4.hours) }
  let!(:assignment) { shift.shift_assignments.create!(person: person, position: 1) }

  before do
    create(:staffing_finalization, organization: org, week_start: shift_at.to_date.beginning_of_week)
    post handle_signin_path, params: { email_address: user.email_address, password: password }
  end

  it "lists the shift while you're on it and drops it once you can't make it" do
    travel_to Time.zone.local(2026, 11, 10, 9, 0) do
      get my_dashboard_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Zamboni driver")

      assignment.decline!(reason: "Sick")
      get my_dashboard_path
      expect(response.body).not_to include("Zamboni driver")
    end
  end
end
