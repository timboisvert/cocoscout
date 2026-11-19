# frozen_string_literal: true

require "rails_helper"

# A production's shared folder (Tim, 2026-11-19): one link to Google Drive,
# Dropbox, or OneDrive with a name, set in Production settings → Documents and
# shown next to the documents to everyone in the production.
RSpec.describe "A production's shared folder", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let(:production) { create(:production, organization: org, name: "Starlet") }
  let(:drive_url) { "https://drive.google.com/drive/folders/1AbCdEf" }

  def sign_in_as(user)
    post handle_signin_path, params: { email_address: user.email_address, password: password }
  end

  describe "the link itself" do
    it "takes Google Drive, Dropbox, and OneDrive links, over https only" do
      {
        "https://drive.google.com/drive/folders/x" => :google_drive,
        "https://docs.google.com/document/d/x/edit" => :google_drive,
        "https://www.dropbox.com/scl/fo/x" => :dropbox,
        "https://1drv.ms/f/s!x" => :onedrive,
        "https://starlet-my.sharepoint.com/:f:/g/x" => :onedrive
      }.each do |url, provider|
        production.documents_link_url = url
        expect(production).to be_valid, url
        expect(production.documents_link_provider).to eq(provider)
      end

      [ "https://example.com/files", "http://drive.google.com/drive/folders/x", "https://drive.google.com.evil.io/x", "not a link" ].each do |url|
        production.documents_link_url = url
        expect(production).not_to be_valid, url
      end
    end

    it "is named after the service when no name is given, and the name goes with the link" do
      production.update!(documents_link_url: drive_url, documents_link_name: "")
      expect(production.documents_link_name).to eq("Google Drive")

      production.update!(documents_link_url: "")
      expect(production.reload.documents_link_url).to be_nil
      expect(production.documents_link_name).to be_nil
    end
  end

  describe "settings" do
    before { sign_in_as(owner) }

    it "lets a manager save the folder and remove it" do
      get edit_manage_production_path(production)
      expect(response.body).to include("Shared folder", 'name="production[documents_link_url]"')

      patch update_documents_link_manage_production_path(production),
            params: { production: { documents_link_url: drive_url, documents_link_name: "Rehearsal files" } }
      expect(response).to redirect_to(edit_manage_production_path(production, tab: 2))
      expect(production.reload.documents_link_name).to eq("Rehearsal files")

      get edit_manage_production_path(production)
      expect(response.body).to include("Remove the shared folder?", "Shared folder on Google Drive")

      patch update_documents_link_manage_production_path(production), params: { production: { documents_link_url: "" } }
      expect(production.reload.documents_link_url).to be_nil
    end

    it "turns away a link from somewhere else and keeps the old one" do
      production.update!(documents_link_url: drive_url)
      patch update_documents_link_manage_production_path(production),
            params: { production: { documents_link_url: "https://example.com/x" } }
      expect(flash[:alert]).to include("Google Drive, Dropbox, or OneDrive")
      expect(production.reload.documents_link_url).to eq(drive_url)
    end

    it "is managers' only" do
      viewer = create(:user, password: password)
      create(:organization_role, user: viewer, organization: org)
      sign_in_as(viewer)
      patch update_documents_link_manage_production_path(production), params: { production: { documents_link_url: drive_url } }
      expect(production.reload.documents_link_url).to be_nil
    end

    it "shows on the production's Documents page, with a pointer to settings when there's none" do
      get manage_production_documents_path(production)
      expect(response.body).to include("Link the folder in the production")

      production.update!(documents_link_url: "https://www.dropbox.com/scl/fo/x", documents_link_name: "Scripts")
      get manage_production_documents_path(production)
      expect(response.body).to include("Scripts", "Shared folder on Dropbox", 'href="https://www.dropbox.com/scl/fo/x"')
    end
  end

  describe "on My" do
    let(:member) { create(:user, password: password) }
    let!(:member_person) { create(:person, user: member).tap { |p| member.update!(default_person: p) } }
    let(:pool) { production.talent_pool }

    before { production.update!(documents_link_url: drive_url, documents_link_name: "Rehearsal files") }

    it "is shown to the talent pool on My Documents and the production's Documents tab, with no documents at all" do
      TalentPoolMembership.create!(talent_pool: pool, member: member_person)
      sign_in_as(member)

      get my_documents_path
      expect(response.body).to include("Starlet", "Rehearsal files", "Shared folder on Google Drive")
      expect(response.body).not_to include("No documents have been shared with you yet.")

      get my_production_path(production)
      expect(response.body).to include("Rehearsal files")
      expect(response.body).not_to include("No documents have been shared with the cast yet.")
    end

    it "is shown to a talent pool member through their group" do
      group = create(:group)
      GroupMembership.create!(group: group, person: member_person)
      TalentPoolMembership.create!(talent_pool: pool, member: group)
      sign_in_as(member)

      get my_documents_path
      expect(response.body).to include("Rehearsal files")
    end

    it "is shown to the production team" do
      create(:person, user: owner).tap { |p| owner.update!(default_person: p) }
      sign_in_as(owner)
      get my_documents_path
      expect(response.body).to include("Rehearsal files")
    end

    it "isn't shown to someone outside the production" do
      sign_in_as(member)
      get my_documents_path
      expect(response.body).not_to include("Rehearsal files")
    end
  end
end
