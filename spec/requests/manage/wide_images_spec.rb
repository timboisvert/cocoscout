# frozen_string_literal: true

require "rails_helper"

# Every production has a poster (3:4) and a wide image (16:9); any show can
# override either. Ticket pages lead with, in order: the show's wide image,
# the show's poster, the production's wide image, the production's poster —
# always shown whole.
RSpec.describe "Wide images", type: :request do
  let(:password) { "Password123!" }
  let(:manager) { create(:user, email_address: "boisvert@gmail.com", password: password) }
  let(:org) { create(:organization, :pro, owner: manager) }
  let(:production) { create(:production, organization: org, name: "Improvised Animorphs") }
  let(:show) { create(:show, production: production, date_and_time: 5.days.from_now) }

  def picture
    fixture_file_upload("test_image.png", "image/png")
  end

  before do
    create(:organization_role, :manager, user: manager, organization: org)
    post handle_signin_path, params: { email_address: manager.email_address, password: password }
    get manage_path
  end

  it "picks the ticket page image in Tim's order" do
    expect(show.ticket_page_image).to be_nil

    production.posters.create!(image: picture, name: "Poster", is_primary: true)
    expect(show.reload.ticket_page_image.to_h.slice(:kind, :owner)).to eq(kind: :poster, owner: :production)

    production.wide_image.attach(picture)
    expect(show.reload.ticket_page_image.to_h.slice(:kind, :owner)).to eq(kind: :wide, owner: :production)

    show.poster.attach(picture)
    expect(show.reload.ticket_page_image.to_h.slice(:kind, :owner)).to eq(kind: :poster, owner: :show)

    show.wide_image.attach(picture)
    expect(show.reload.ticket_page_image.to_h.slice(:kind, :owner)).to eq(kind: :wide, owner: :show)
  end

  it "won't take a file that isn't a picture" do
    production.wide_image.attach(fixture_file_upload("test_document.pdf", "application/pdf"))
    expect(production).not_to be_valid
    expect(production.errors[:wide_image]).to include("must be a JPG, PNG or WebP")
  end

  it "uploads and removes the production's wide image in Visual Assets" do
    get edit_manage_production_path(production, tab: 1)
    expect(response.body).to include("Wide image (16:9)", "No wide image yet", "Save wide image")

    patch manage_wide_image_production_visual_asset_path(production), params: { production: { wide_image: picture } }
    expect(response).to redirect_to(edit_manage_production_path(production, tab: 1))
    expect(flash[:notice]).to eq("Wide image saved.")
    expect(production.reload.wide_image).to be_attached

    get edit_manage_production_path(production, tab: 1)
    expect(response.body).to include("Delete the wide image?", "Delete wide image")

    delete manage_wide_image_production_visual_asset_path(production)
    expect(flash[:notice]).to eq("Wide image removed.")
  end

  # Tim (2026-10-02): the poster and the wide image are equals, side by side,
  # with what each is for; no logo; shows with their own images are counted
  # and pointed to, not shown.
  it "explains the two images, side by side, and points to shows with their own" do
    get edit_manage_production_path(production, tab: 1)
    page = response.body
    expect(page).to include("How #{production.name} looks everywhere", "Poster · 3:4, tall", "Wide image · 16:9",
                            "Poster (3:4)", "Wide image (16:9)", "No poster yet", "Add a poster")
    expect(page).not_to include("Logo", "Posters used by individual shows")
    expect(page).to include("None. Every show and event uses the two images above.")

    show.update!(wide_image: picture)
    get edit_manage_production_path(production, tab: 1)
    expect(response.body).to include("1 show or event uses its own poster or wide image", "See which ones",
                                     manage_edit_show_path(production, show, tab: 4), "Own wide image")
  end

  it "lets one show use its own wide image, and drop it again" do
    patch manage_show_path(production, show), params: { show: { wide_image: picture } }
    expect(show.reload.wide_image).to be_attached

    get manage_edit_show_path(production, show)
    expect(response.body).to include("This show's own wide image.", "Use Improvised Animorphs")

    patch manage_show_path(production, show), params: { show: { remove_wide_image: "1" } }
    expect(show.reload.wide_image).not_to be_attached
  end

  describe "in Ticketing" do
    let!(:listing) do
      TicketingProfile.for(org).update!(enabled: true, slug: "starsandgarters")
      TicketListing.create!(show: show, status: "on_sale").tap { |l| l.ticket_tiers.create!(name: "General", price_cents: 2_000) }
    end

    it "says plainly whether there's a wide image, and which picture the page uses" do
      get manage_edit_ticket_listing_path(listing, section: "page")
      expect(response.body).to include("Ticket page image", "No wide image or poster yet")

      production.posters.create!(image: picture, name: "Poster", is_primary: true)
      get manage_edit_ticket_listing_path(listing, section: "page")
      expect(response.body).to include("No wide image, so the page uses the production&#39;s poster")

      show.wide_image.attach(picture)
      get manage_edit_ticket_listing_path(listing, section: "page")
      expect(response.body).to include("This show&#39;s wide image.")

      # The show's page itself only points at Settings for it.
      get manage_ticket_listing_path(listing)
      expect(response.body).to include("page and image")
      expect(response.body).not_to include("Ticket page image")
    end

    it "leads the public page with the picture, whole" do
      get tickets_event_path(org: "starsandgarters", event: listing.slug)
      expect(response.body).not_to include("og:image")

      production.posters.create!(image: picture, name: "Poster", is_primary: true)
      get tickets_event_path(org: "starsandgarters", event: listing.slug)
      expect(response.body).to include("og:image", "max-h-[28rem] w-auto h-auto")

      production.wide_image.attach(picture)
      get tickets_event_path(org: "starsandgarters", event: listing.slug)
      expect(response.body).to include("w-full h-auto rounded-2xl")
      expect(response.body).not_to include("object-cover")
    end

    it "leads the production's page with the chosen date's own picture (Tim, 2026-10-08)" do
      production.wide_image.attach(picture)
      later = create(:show, production: production, date_and_time: 12.days.from_now)
      TicketListing.create!(show: later, status: "on_sale").ticket_tiers.create!(name: "General", price_cents: 2_000)
      later.wide_image.attach(picture)
      date_art = later.reload.wide_image.blob.signed_id
      production_art = production.reload.wide_image.blob.signed_id

      get tickets_event_path(org: "starsandgarters", event: production.public_key, date: later.ticket_listing.slug)
      expect(response.body).to include(date_art)
      expect(response.body).to match(/og:image" content="[^"]*#{date_art}/)

      # The first date has no art of its own, so it shows the production's;
      # a link to the production shares the production's picture.
      get tickets_event_path(org: "starsandgarters", event: production.public_key)
      expect(response.body).not_to include(date_art)
      expect(response.body).to match(/og:image" content="[^"]*#{production_art}/)
    end
  end
end
