# frozen_string_literal: true

require "rails_helper"

# Appendixes are managed on the Prepare step and render into the document
# above the signature block.
RSpec.describe "Contract appendixes", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:template) { org.contract_templates.create!(name: "Standard", content: "<p>Agreement for {{contractor_name}}</p>") }
  let!(:contract) do
    create(:contract, :active, organization: org, contractor_name: "Quinn James",
                               signing_mode: :esign, contract_template: template)
  end

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  it "offers the editor on the Prepare step" do
    get manage_prepare_contract_wizard_path(contract)

    expect(response.body).to include("Appendixes")
    expect(response.body).to include("Add appendix")
  end

  it "letters them automatically as they're added" do
    post manage_contract_contract_appendixes_path(contract, return_to: "prepare"),
         params: { contract_appendix: { title: "Tech Rider", body: "<p>Two monitors.</p>" } }
    post manage_contract_contract_appendixes_path(contract, return_to: "prepare"),
         params: { contract_appendix: { title: "Hospitality", body: "<p>Coffee.</p>" } }

    headings = contract.contract_appendixes.ordered.map(&:heading)
    expect(headings).to eq([ "Appendix A — Tech Rider", "Appendix B — Hospitality" ])
    expect(response).to redirect_to(manage_prepare_contract_wizard_path(contract))
  end

  it "puts them in the document, after the deal terms" do
    post manage_contract_contract_appendixes_path(contract),
         params: { contract_appendix: { title: "Tech Rider", body: "<p>Two monitors.</p>" } }

    doc = contract.reload.render_signable_document
    expect(doc).to include("Appendix A — Tech Rider")
    expect(doc).to include("Two monitors.")
  end

  it "re-letters what's left when one is removed, so there's no gap" do
    post manage_contract_contract_appendixes_path(contract), params: { contract_appendix: { title: "One", body: "<p>a</p>" } }
    post manage_contract_contract_appendixes_path(contract), params: { contract_appendix: { title: "Two", body: "<p>b</p>" } }
    first = contract.contract_appendixes.ordered.first

    delete manage_contract_contract_appendix_path(contract, first)

    remaining = contract.reload.contract_appendixes.ordered
    expect(remaining.map(&:heading)).to eq([ "Appendix A — Two" ])
  end

  it "edits in place" do
    post manage_contract_contract_appendixes_path(contract), params: { contract_appendix: { title: "Rider", body: "<p>Old.</p>" } }
    appendix = contract.contract_appendixes.first

    patch manage_contract_contract_appendix_path(contract, appendix),
          params: { contract_appendix: { title: "Tech Rider", body: "<p>New.</p>" } }

    expect(appendix.reload.title).to eq("Tech Rider")
    expect(appendix.body_html).to include("New.")
  end

  it "won't touch another org's contract" do
    other = create(:contract, :active, organization: create(:organization, owner: create(:user)))

    post manage_contract_contract_appendixes_path(other), params: { contract_appendix: { title: "X", body: "<p>x</p>" } }

    # The app's catch-all turns the scoped lookup miss into a 404 page.
    expect(response).to have_http_status(:not_found)
    expect(other.contract_appendixes.count).to eq(0)
  end
end
