# frozen_string_literal: true

require "rails_helper"

# Regression: per-form CSRF tokens (Rails 8 defaults) are minted for the form's
# action at render time. The scheduling page's modal forms are rendered with
# `url: "#"` and their action is rewritten by Stimulus (shift-assign, shift-edit,
# shift-split), so their default per-form token would be minted for "#" and
# rejected with a 422 in production. The fix passes the session-wide token via
# `authenticity_token: form_authenticity_token`. The test env disables forgery
# protection, so this spec re-enables it and submits the token actually rendered
# in the form to the path the JS would set.
RSpec.describe "Manage::Staffing scheduling JS-retargeted form CSRF", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }

  let(:foh) { create(:house_role, organization: org, name: "FOH") }
  let(:staffer) { create(:person, name: "Quinn Qualified") }
  let!(:membership) { create(:organization_staff_member, organization: org, person: staffer) }

  let(:week_start) { Date.current.beginning_of_week }
  let!(:shift) do
    create(:shift, organization: org, house_role: foh,
                   starts_at: (week_start + 1).in_time_zone.change(hour: 18),
                   ends_at: (week_start + 1).in_time_zone.change(hour: 22))
  end

  before do
    org.people << staffer
    membership.house_roles << foh
    # Sign in while forgery protection is still off (the default in test),
    # then turn it on so the submissions below are actually verified.
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
    ActionController::Base.allow_forgery_protection = true
  end

  after { ActionController::Base.allow_forgery_protection = false }

  def scrape_token(css_selector)
    get manage_staffing_scheduling_path(week_start: week_start.to_s)
    expect(response).to have_http_status(:ok)
    form = Nokogiri::HTML(response.body).at_css(css_selector)
    expect(form).to be_present
    form.at_css('input[name="authenticity_token"]')&.[]("value")
  end

  it "accepts the assign form's rendered token at the JS-set path" do
    token = scrape_token('form[data-shift-assign-target="form"]')
    expect(token).to be_present

    expect {
      post manage_assign_staffing_shift_path(shift),
           params: { person_id: staffer.id, authenticity_token: token }
    }.to change(ShiftAssignment, :count).by(1)
    expect(response.status).not_to eq(422)
  end

  it "accepts the edit form's rendered token at the JS-set path" do
    token = scrape_token('form[data-shift-edit-target="form"]')
    expect(token).to be_present

    patch manage_update_staffing_shift_path(shift),
          params: { authenticity_token: token,
                    shift: { starts_at: shift.starts_at, ends_at: shift.ends_at + 30.minutes } }
    expect(response.status).not_to eq(422)
    expect(shift.reload.ends_at).to eq((week_start + 1).in_time_zone.change(hour: 22, min: 30))
  end

  it "rejects a submission without a token (sanity check that protection is on)" do
    expect {
      post manage_assign_staffing_shift_path(shift), params: { person_id: staffer.id }
    }.not_to change(ShiftAssignment, :count)
    expect(response.status).to eq(422)
  end
end
