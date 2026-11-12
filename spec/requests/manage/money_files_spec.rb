# frozen_string_literal: true

require "rails_helper"

# Money documents are served through a route that checks who is asking;
# their keys live under the organization in storage.
RSpec.describe "Manage::MoneyFiles", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let(:png) { Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/test_image.png"), "image/png") }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  it "hands the organization's own manager a short-lived address, keyed under the organization, and nobody else" do
    bill = org.bills.create!(vendor_name: "Lumber", amount_cents: 1_000, issued_on: Date.current, due_on: Date.current + 7, category_key: "production", document: png)
    attachment = bill.document.attachment
    expect(bill.document.blob.reload.key).to start_with("organizations/#{org.id}/bills/#{bill.id}/documents/")

    get manage_money_bill_path(bill)
    expect(response.body).to include(manage_money_file_path(attachment))
    expect(response.body).not_to include("/rails/active_storage/blobs")

    get manage_money_file_path(attachment)
    expect(response).to have_http_status(:found)
    expect(response.location).to include(bill.document.blob.key.split("/").last).or include("rails/active_storage/disk")

    other_owner = create(:user, password: password)
    other = create(:organization, :pro, owner: other_owner)
    create(:organization_role, :manager, user: other_owner, organization: other)
    get signout_path
    post handle_signin_path, params: { email_address: other_owner.email_address, password: password }
    get select_organization_path
    get manage_money_file_path(attachment)
    expect(response).to have_http_status(:not_found)
  end
end
