# frozen_string_literal: true

require "rails_helper"

# The App Store's support URL: a public page that says how to reach a person.
RSpec.describe "Support page", type: :request do
  it "is public, says the email, and answers the questions the app raises" do
    get support_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("support@cocoscout.com", "delete my account", "opens in Safari", "Notifications")
    expect(response.body).to include(%(href="#{privacy_path}"), %(href="#{terms_path}"))
    expect(response.body).not_to include("theater")
  end

  it "is linked from the marketing footer" do
    get root_path
    expect(response.body).to include(%(href="#{support_path}"))
  end
end
