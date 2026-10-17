# frozen_string_literal: true

require "rails_helper"

# A contracted production's settings page has a Contract information card.
# Its Pro mark sits in the card's header, as on every Pro card, not in the
# body beside View Contract (Tim, 2026-10-16).
RSpec.describe "Production settings — Contract information", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org, production_type: "third_party") }
  let!(:contract) { create(:contract, :active, organization: org, production: production, contractor_name: "Nuns4Fun") }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  it "marks the card Pro in its header, with View Contract in the body" do
    get edit_manage_production_path(production)
    html = response.body.gsub(/\s+/, " ")

    # The basics card above names the contractor too, so read from the card down.
    card = html[html.index("Contract information")..]
    expect(card).to include("Pro feature", "Nuns4Fun", "View Contract", manage_contract_path(contract))
    expect(card.index("Pro feature")).to be < card.index("Nuns4Fun")
    expect(card.index("Nuns4Fun")).to be < card.index("View Contract")
  end
end
