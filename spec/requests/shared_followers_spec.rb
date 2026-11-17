# frozen_string_literal: true

require "rails_helper"

# Followers through the contract (Tim, 2026-11-17): a mailing list for a
# contractor's shows, collected on the selling organization's checkout and
# shared with everyone on the contract. On My when the contract isn't
# connected to an organization of their own; in that organization once it
# is: read-only on the free plan, its own followers on Pro.
RSpec.describe "Followers shared through a contract", type: :request do
  include ActiveJob::TestHelper

  let(:password) { "Password123!" }
  # The organization that sells the tickets and keeps the list.
  let!(:owner) { create(:user, password: password) }
  let!(:owner_person) { create(:person, user: owner).tap { |p| owner.update!(default_person: p) } }
  let!(:venue) { create(:organization, :pro, owner: owner, name: "Stars and Garters") }
  # The contractor, and someone else on the contract.
  let!(:user) { create(:user, password: password) }
  let!(:person) { create(:person, user: user, name: "Thea Example").tap { |p| user.update!(default_person: p) } }
  let!(:contractor) { create(:contractor, organization: venue, person: person, name: "Thea Example") }
  let!(:production) { create(:production, organization: venue, production_type: "third_party", name: "The Holly Problem") }
  let!(:contract) do
    create(:contract, :active, organization: venue, production: production, contractor: contractor,
                               contractor_name: contractor.name, contractor_email: contractor.email)
  end
  let!(:list) { venue.mailing_lists.create!(kind: "group", name: "Thea's shows", contractor: contractor) }

  before { create(:organization_role, :manager, user: owner, organization: venue) }

  def sign_in(who)
    post handle_signin_path, params: { email_address: who.email_address, password: password }
  end

  def follow!(email, name, mailing_list: list)
    follower = Follower.for!(mailing_list.organization, email, name: name)
    mailing_list.mailing_list_memberships.create!(follower: follower)
    follower.follower_sources.create!(kind: "manual", mailing_list: mailing_list, occurred_at: Time.current)
    follower
  end

  # The contractor's own organization, connected to the contract.
  def connected_organization!(**traits)
    theirs = create(:organization, owner: user, name: "Thea Presents", **traits)
    create(:organization_role, :manager, user: user, organization: theirs)
    their_production = create(:production, organization: theirs, name: "The Holly Problem")
    connection = ContractConnections.request!(contract: contract, user: user, organization: theirs, production: their_production)
    ContractConnections.accept!(connection, user: owner)
    theirs
  end

  describe "at checkout" do
    it "puts the contractor's box on every production under a live contract, ahead of the main list, saying who can email them" do
      boxes = MailingList.for_checkout(production)

      expect(boxes.map(&:name)).to eq([ "Thea's shows", "Stars and Garters" ])
      expect(boxes.first.box_words).to eq("Send me news about Thea's shows")
      expect(boxes.first.box_note).to eq("Thea Example and Stars and Garters can both email you about them.")
      expect(boxes.last.box_note).to be_nil
    end

    it "leaves when the contract is no longer live, and isn't on a production the contractor has nothing to do with" do
      other = create(:production, organization: venue, name: "House Show")
      expect(MailingList.for_checkout(other).map(&:name)).to eq([ "Stars and Garters" ])

      contract.update_columns(status: "completed")
      expect(MailingList.for_checkout(production).map(&:name)).to eq([ "Stars and Garters" ])
    end

    it "says nothing about sharing when the organization keeps the list to itself" do
      list.update!(shared_with_contractor: false)
      expect(list.box_note).to be_nil
    end
  end

  describe "on the list's own page" do
    before do
      sign_in(owner)
      post set_organization_path(id: venue.id)
    end

    it "says who the list is for and what it collects from, and can be changed" do
      get manage_mailing_list_path(list)
      expect(response.body).to include("Who this list is for").and include("Thea Example").and include("From the contract")

      patch manage_mailing_list_contractor_path(list), params: { contractor_id: "", shared_with_contractor: "1" }
      expect(list.reload.contractor).to be_nil

      patch manage_mailing_list_contractor_path(list), params: { contractor_id: contractor.id, shared_with_contractor: "0" }
      expect(list.reload).to have_attributes(contractor_id: contractor.id, shared_with_contractor: false)
    end
  end

  describe "a production's Checkout boxes" do
    let!(:holiday) { venue.mailing_lists.create!(kind: "group", name: "Holiday shows") }

    before do
      TicketingProfile.for(venue).update!(enabled: true)
      sign_in(owner)
      post set_organization_path(id: venue.id)
    end

    it "lists every box with why it's there, and adds or removes one of the other lists" do
      get manage_edit_production_ticketing_path(production, section: "boxes")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Boxes on this production").and include("From your contract with Thea Example").and include("On every production")
      expect(response.body).not_to include("Chosen for this production")

      patch manage_update_production_ticketing_path(production, section: "boxes"), params: { mailing_list_ids: [ holiday.id ] }
      expect(MailingList.for_checkout(production).map(&:name)).to eq([ "Thea's shows", "Holiday shows", "Stars and Garters" ])
      follow_redirect!
      expect(response.body).to include("Chosen for this production")

      # The contract's list isn't something to untick here: sending nothing removes only the chosen one.
      patch manage_update_production_ticketing_path(production, section: "boxes"), params: { mailing_list_ids: [ "" ] }
      expect(MailingList.for_checkout(production).map(&:name)).to eq([ "Thea's shows", "Stars and Garters" ])
    end
  end

  describe "My Followers" do
    before { follow!("dana@example.com", "Dana Whitfield") }

    it "shows the contractor everyone on the list, hand-added people included, with a download" do
      sign_in(user)
      get my_followers_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("My Followers").and include("Dana Whitfield").and include("dana@example.com")
        .and include("Added by Stars and Garters").and include("Nothing is sent from this page")

      get my_followers_download_path(list)
      expect(response.media_type).to eq("text/csv")
      expect(response.body).to include("Dana Whitfield,dana@example.com")
    end

    it "is for everyone on the contract, not only the contractor" do
      colleague = create(:user, password: password)
      ContractPerson.create!(contract: contract, person: create(:person, user: colleague, name: "Robin Colleague"))

      sign_in(colleague)
      get my_followers_path
      expect(response.body).to include("Dana Whitfield")
    end

    it "is in the My menu only for someone a list is shared with, and nobody else can reach it" do
      sign_in(user)
      get my_contracts_path
      expect(response.body).to include(my_followers_path)

      stranger = create(:user, password: password)
      create(:person, user: stranger)
      get signout_path
      sign_in(stranger)
      get my_followers_path
      expect(response).to redirect_to(my_dashboard_path)
      get my_followers_download_path(list)
      expect(response).to redirect_to(my_followers_path)
    end

    it "leaves out someone who stopped following, and closes when sharing is switched off" do
      Follower.find_by!(email: "dana@example.com").update!(status: "unsubscribed")
      follow!("marcus@example.com", "Marcus Oyelaran")
      sign_in(user)

      get my_followers_path
      expect(response.body).to include("Marcus Oyelaran")
      expect(response.body).not_to include("Dana Whitfield")

      list.update!(shared_with_contractor: false)
      get my_followers_path
      expect(response).to redirect_to(my_dashboard_path)
    end

    it "keeps the followers after the contract ends" do
      contract.update_columns(status: "completed")
      sign_in(user)
      get my_followers_path

      expect(response.body).to include("Dana Whitfield")
    end
  end

  describe "in a connected organization on the free plan" do
    let!(:theirs) { connected_organization! }

    before do
      follow!("dana@example.com", "Dana Whitfield")
      sign_in(user)
      post set_organization_path(id: theirs.id)
    end

    it "opens Mailing lists as a read-only page of the shared followers, with a download and no sending" do
      get manage_mailing_lists_path
      expect(response).to redirect_to(manage_shared_followers_path)
      follow_redirect!

      expect(response.body).to include("From Stars and Garters").and include("Dana Whitfield").and include("Emailing them from CocoScout is part of Pro")
      get manage_shared_followers_download_path(list)
      expect(response.body).to include("dana@example.com")
      expect(theirs.followers.count).to eq(0)
    end

    it "moves the list off My, with a pointer to where it lives now" do
      get my_followers_path
      expect(response.body).to include("is in Thea Presents now")
      expect(response.body).not_to include("Dana Whitfield")

      post set_organization_path(id: theirs.id), params: { return_to: manage_shared_followers_path }
      expect(response).to redirect_to(manage_shared_followers_path)
      post set_organization_path(id: theirs.id), params: { return_to: "https://example.com/elsewhere" }
      expect(response).not_to redirect_to("https://example.com/elsewhere")
    end

    it "opens Ticketing as the dates the other organization sells, not the paywall" do
      get manage_ticketing_path
      expect(response).to redirect_to(manage_sold_elsewhere_path)
      follow_redirect!
      expect(response.body).to include("Selling tickets yourself is part of Pro")
    end

    it "still shows the paywall to a free organization with nothing shared" do
      list.update!(shared_with_contractor: false)
      get manage_mailing_lists_path
      expect(response).to have_http_status(:payment_required)
    end
  end

  describe "in a connected organization on Pro" do
    it "makes the followers the organization's own, on a list of its own, and keeps bringing new ones" do
      follow!("dana@example.com", "Dana Whitfield")
      theirs = nil
      perform_enqueued_jobs { theirs = connected_organization!(comped_indefinitely: true) }

      received = theirs.mailing_lists.find_by!(source_list: list)
      expect(received.name).to eq("From Stars and Garters")
      expect(received.followers.pluck(:email)).to eq([ "dana@example.com" ])
      expect(received.followers.first.follower_sources.first.label).to start_with("From Stars and Garters")

      perform_enqueued_jobs { follow!("marcus@example.com", "Marcus Oyelaran") }
      expect(received.followers.pluck(:email)).to contain_exactly("dana@example.com", "marcus@example.com")

      sign_in(user)
      post set_organization_path(id: theirs.id)
      get manage_mailing_list_path(received)
      expect(response.body).to include("Shared through your contract").and include("Dana Whitfield")
    end

    it "never re-adds someone who unsubscribed from the organization, and never takes anyone away" do
      theirs = nil
      perform_enqueued_jobs { theirs = connected_organization!(comped_indefinitely: true) }
      Follower.for!(theirs, "dana@example.com").update!(status: "unsubscribed")
      perform_enqueued_jobs { follow!("dana@example.com", "Dana Whitfield") }
      perform_enqueued_jobs { follow!("marcus@example.com", "Marcus Oyelaran") }

      received = theirs.mailing_lists.find_by!(source_list: list)
      expect(received.followers.pluck(:email)).to eq([ "marcus@example.com" ])

      # Sharing stops: the ones already theirs stay.
      list.update!(shared_with_contractor: false)
      expect(SharedFollowers.sync!(theirs)).to eq(0)
      expect(received.reload.followers.pluck(:email)).to eq([ "marcus@example.com" ])
    end
  end
end
