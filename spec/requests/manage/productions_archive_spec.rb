# frozen_string_literal: true

require "rails_helper"

# Archiving a production hides it from lists and pickers without deleting it.
# Org owners/managers archive from Production Settings and bring it back from
# the Productions page's Archived filter.
RSpec.describe "Manage productions archive", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org, name: "One Night Only") }
  let!(:other) { create(:production, organization: org, name: "Still Running") }

  def sign_in_as(user)
    post handle_signin_path, params: { email_address: user.email_address, password: password }
  end

  context "as the organization's owner" do
    before { sign_in_as(owner) }

    it "archives from settings, hides it from the list, and shows it under Archived with Unarchive" do
      get edit_manage_production_path(production)
      expect(response.body).to include("Archive this production")

      post archive_manage_production_path(production)
      expect(response).to redirect_to(manage_productions_path)
      expect(production.reload).to be_archived

      # The flash names the production, so look for its card (its settings link).
      get manage_productions_path
      expect(response.body).not_to include(edit_manage_production_path(production))
      expect(response.body).to include(edit_manage_production_path(other))
      expect(response.body).to include("Archived")

      get manage_productions_path(status: "archived")
      # The page itself: the organization menu names the one live production on every page.
      page = Nokogiri::HTML(response.body).at_css("main").to_html
      expect(page).to include(edit_manage_production_path(production))
      expect(page).not_to include(edit_manage_production_path(other))
      expect(page).to include("Unarchive")

      get edit_manage_production_path(production)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("This production is archived")
    end

    it "unarchives back onto the main list" do
      production.archive!

      post unarchive_manage_production_path(production)
      expect(response).to redirect_to(manage_productions_path)
      expect(production.reload).not_to be_archived

      get manage_productions_path
      expect(response.body).to include("One Night Only")
    end

    it "drops an archived production from the current selection" do
      get manage_production_path(production)
      post archive_manage_production_path(production)

      get manage_productions_path
      expect(session[:current_production_id_for_organization]["#{owner.id}_#{org.id}"]).to be_nil
    end

    it "still honors the Type filter inside the Archived view" do
      production.archive!
      create(:production, organization: org, name: "Old Course", production_type: "course", archived_at: Time.current)

      get manage_productions_path(status: "archived", filter: "course")
      expect(response.body).to include("Old Course")
      expect(response.body).not_to include("One Night Only")
    end
  end

  context "as a producer with access to the production but no org role" do
    let(:producer) { create(:user, password: password) }

    before do
      create(:organization_role, user: producer, organization: org, company_role: "member")
      create(:production_permission, user: producer, production: production, role: "manager")
      sign_in_as(producer)
    end

    it "cannot archive and sees no Status filter" do
      post archive_manage_production_path(production)
      expect(production.reload).not_to be_archived

      get manage_productions_path
      expect(response.body).not_to include("Archived")
    end
  end
end
