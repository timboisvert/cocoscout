# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Superadmin content templates: push", type: :request do
  let(:superadmin) { create(:user, email_address: "boisvert@gmail.com", password: "Password123!") }
  let!(:template) do
    create(:content_template, :message_channel, key: "call_time", name: "Call time", subject: "Call time for {{topic}}")
  end

  before { post handle_signin_path, params: { email_address: superadmin.email_address, password: "Password123!" } }

  it "lets the superadmin write the push text, switch the push off, and see both" do
    get content_template_preview_path(template)
    expect(response.body).to include("Push Notification Preview", "No push text written; the subject is used.")

    patch content_template_update_path(template),
          params: { content_template: { push: "0", push_body: "Be there for {{topic}}" } }
    expect(template.reload).to have_attributes(push: false, push_body: "Be there for {{topic}}")

    get content_templates_path
    expect(response.body).to include("Quiet")

    get content_template_preview_path(template)
    expect(response.body).to include("(off for this template)", "Be there for")
    expect(response.body).not_to include("No push text written")

    get content_template_edit_path(template)
    expect(response.body).to include("Push to phones", "Push Notification")
  end
end
