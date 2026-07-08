# frozen_string_literal: true

require "rails_helper"

# Regression: an org manager whose session pointed at an archived production was
# redirected off every production-scoped page (and org-level pages like Messages)
# because the access guard used accessible_productions, which excludes archived.
RSpec.describe "Manage archived production access", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:archived_production) { create(:production, organization: org, archived_at: Time.current) }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  it "lets a manager open an ARCHIVED production instead of redirecting to /manage/productions" do
    get manage_production_path(archived_production)

    expect(response).to have_http_status(:ok)
    expect(response).not_to redirect_to(manage_productions_path)
  end

  it "still blocks a user with no role in the org" do
    outsider = create(:user, password: password)
    # Give them access to some other org so they can reach /manage at all.
    other_org = create(:organization, owner: outsider)
    create(:organization_role, :manager, user: outsider, organization: other_org)
    post handle_signin_path, params: { email_address: outsider.email_address, password: password }

    get manage_production_path(archived_production)
    expect(response).not_to have_http_status(:ok)
  end
end
