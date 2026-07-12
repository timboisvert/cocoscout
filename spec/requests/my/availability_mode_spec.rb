# frozen_string_literal: true

require "rails_helper"

RSpec.describe "My::Shifts availability mode", type: :request do
  let(:password) { "Password123!" }
  let(:user) { create(:user, password: password) }
  let!(:person) { create(:person, user: user, email: user.email_address) }

  before { post handle_signin_path, params: { email_address: user.email_address, password: password } }

  it "defaults to unavailable mode" do
    expect(person.availability_mode).to eq("unavailable")
  end

  it "switches to available mode and clears existing marks" do
    person.staff_unavailabilities.create!(date: Date.current + 3, scope: :all_day)

    post my_set_shift_availability_mode_path, params: { mode: "available" }, as: :json
    expect(response).to have_http_status(:ok)
    expect(person.reload.availability_mode).to eq("available")
    expect(person.staff_unavailabilities).to be_empty
  end

  it "rejects an invalid mode" do
    post my_set_shift_availability_mode_path, params: { mode: "whenever" }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(person.reload.availability_mode).to eq("unavailable")
  end
end
