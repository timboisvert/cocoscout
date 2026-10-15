# frozen_string_literal: true

require "rails_helper"

# Custom questions on sign-up forms are off until answers are saved
# (SignUpForm::CUSTOM_QUESTIONS; Tim, 2026-10-15): nothing stored what people
# typed, so neither producers nor performers see them for now.
RSpec.describe "Sign-up form questions, switched off", type: :request do
  let(:password) { "Password123!" }
  let(:manager) { create(:user, password: password) }
  let(:org) { create(:organization, :pro, owner: manager) }
  let(:production) { create(:production, organization: org) }
  let(:form) { create(:sign_up_form, production: production) }

  before do
    create(:organization_role, :manager, user: manager, organization: org)
    create(:question, questionable: form, text: "What will you be performing?")
    post handle_signin_path, params: { email_address: manager.email_address, password: password }
    get manage_path
  end

  it "hides the Questions tab, and the questions on the sign-up page" do
    expect(SignUpForm::CUSTOM_QUESTIONS).to be(false)

    get manage_edit_signups_form_path(production, form)
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(">Questions</button>", "What will you be performing?")

    # Links that used to open the Questions tab land on one that's there.
    get manage_edit_signups_form_path(production, form, tab: 2)
    expect(response.body).to include('data-tabs-initial-tab-value="1"')

    get manage_preview_signups_form_path(production, form)
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("What will you be performing?")
  end
end
