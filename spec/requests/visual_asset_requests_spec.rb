# frozen_string_literal: true

require "rails_helper"

# Visual asset specifications and requests (Tim, 2026-11-19): the
# organization's list, a production's Visual Assets tab, the one no-login
# link, the same page on My Contracts, and the folded notifications.
RSpec.describe "Visual asset requests", type: :request do
  include ActiveJob::TestHelper

  let(:password) { "Password123!" }
  let!(:manager) { create(:user, password: password) }
  let!(:manager_person) { create(:person, user: manager, name: "Tim Boisvert") }
  let!(:org) { create(:organization, :pro, owner: manager, name: "The Lantern Room") }
  let!(:production) { create(:production, organization: org, name: "Late Bloomers", production_type: "third_party") }
  let!(:show) { create(:show, production: production, date_and_time: 3.weeks.from_now) }
  let!(:instagram) do
    AssetSpec.ensure_builtins!(org)
    org.asset_specs.create!(name: "Instagram square", kind: "image", width: 1080, height: 1080, formats: %w[jpg png], position: 5, used_for: "Our Instagram posts")
  end
  let!(:blurb) { org.asset_specs.create!(name: "Short blurb", kind: "text", max_length: 140, position: 6) }

  before do
    VisualAssetTemplates.ensure!
    create(:organization_role, :manager, user: manager, organization: org)
  end

  def sign_in(user)
    post handle_signin_path, params: { email_address: user.email_address, password: password }
  end

  describe "the organization's list" do
    before do
      sign_in(manager)
      get manage_path
    end

    it "shows the built-ins, which can't be removed, and the organization's own" do
      get section_manage_organization_path(org, section: "visual_assets")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Poster", "Wide image", "Show description", "Instagram square", "Short blurb", "Built in")
      poster = org.asset_specs.find_by(builtin: "poster")
      delete manage_asset_spec_path(poster)
      expect(flash[:alert]).to eq("Poster is built in, so it can't be removed.")
      expect(poster.reload.archived_at).to be_nil
    end

    it "adds an image in inches for print" do
      post manage_asset_specs_path, params: { asset_spec: { kind: "image", name: "Print poster", unit: "inches", width: "11", height: "17", dpi: "300",
                                                            formats: [ "", "pdf", "png" ], max_megabytes: "50", required: "0" } }

      spec = org.asset_specs.find_by(name: "Print poster")
      expect([ spec.width, spec.height, spec.dpi, spec.formats, spec.required ]).to eq([ 3300, 5100, 300, %w[pdf png], false ])
      expect(spec.size_words).to eq("11 × 17 inches at 300 DPI (3300 × 5100)")
    end

    it "keeps the poster 3:4 when its smallest width changes" do
      poster = org.asset_specs.find_by(builtin: "poster")
      patch manage_asset_spec_path(poster), params: { asset_spec: { name: "Poster", width: "1200", formats: %w[jpg png], max_megabytes: "10", required: "1" } }

      expect([ poster.reload.width, poster.height ]).to eq([ 1200, 1600 ])
    end

    it "removes one of its own, keeping files productions already have" do
      ProductionAssets.new(production).store_file!(instagram, asset_image(1080, 1080),
                                                   check: AssetCheck.call(instagram, asset_image(1080, 1080)))
      delete manage_asset_spec_path(instagram)

      expect(instagram.reload.archived_at).to be_present
      kept = production.production_assets.additional.last
      expect(kept.name).to eq("Instagram square")
      expect(kept.file).to be_attached
    end

    it "reorders the list" do
      ids = AssetSpec.for(org).images.map(&:id).reverse
      post manage_reorder_asset_specs_path, params: { role_ids: ids }, as: :json

      expect(response).to have_http_status(:ok)
      expect(AssetSpec.for(org).images.map(&:id)).to eq(ids)
    end
  end

  describe "a production's Visual Assets tab" do
    before do
      sign_in(manager)
      get manage_path
    end

    it "lists the organization's items with what is here and what is not" do
      get edit_manage_production_path(production, tab: 1)

      expect(response.body).to include("You have 0 of the 5 items The Lantern Room requires for every production.")
      expect(response.body).to include("Instagram square", "Not here yet. 1:1, at least 1080 × 1080. JPG or PNG.", "Request these", "Additional files")
      # The request starts with plain, businesslike words (Tim, 2026-11-19).
      expect(response.body).to include("The Lantern Room requests the visual assets and written details listed below for Late Bloomers.")
      expect(response.body).not_to include("ready to announce")

      # What is being requested: the images, then the written items,
      # and what's here says "Received" (Tim, 2026-11-19).
      production.update!(wide_image: fixture_file_upload("test_image.png", "image/png"))
      org.asset_specs.find_by(builtin: "description").update_column(:position, -10)
      get edit_manage_production_path(production, tab: 1)
      sheet = response.body[response.body.index("What is being requested")..]
      expect(sheet.index("Instagram square")).to be < sheet.index("Show description")
      expect(sheet).to include("Received")
      expect(sheet).not_to include("Already uploaded")
      expect(sheet).not_to include("Already here")
    end

    # The bar turns green once every item is in, optional ones too (Tim, 2026-11-22).
    it "draws the progress bar pink until every item is in, then green" do
      post manage_request_production_visual_asset_path(production), params: { commit_action: "copy", allow_replace: "1" }
      bar = -> { response.body[/<div class="h-2 ([^"]+)" data-asset-progress-bar/, 1] }

      get edit_manage_production_path(production, tab: 1)
      expect(bar.call).to eq("bg-pink-500")

      allow_any_instance_of(ProductionAssets).to receive(:counts)
        .and_return(ProductionAssets::Counts.new(done: 5, total: 5, missing_required: [], missing_optional: []))
      get edit_manage_production_path(production, tab: 1)
      expect(bar.call).to eq("bg-green-500")
    end

    it "uploads a file that meets the specification, and refuses one that doesn't" do
      post manage_upload_production_visual_asset_path(production), params: { spec_id: instagram.id, file: asset_image(1080, 1350, name: "ig.png") }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["message"]).to include("taller than it is wide")
      expect(production.production_assets.count).to eq(0)

      post manage_upload_production_visual_asset_path(production), params: { spec_id: instagram.id, file: asset_image(1080, 1080) }
      expect(response.parsed_body["ok"]).to be(true)
      asset = production.production_assets.find_by(asset_spec: instagram)
      expect([ asset.width, asset.height, asset.uploaded_by_user, asset.last_change ]).to eq([ 1080, 1080, manager, "added" ])

      get edit_manage_production_path(production, tab: 1)
      expect(response.body).to include("Download original", "Added by Tim Boisvert today")
    end

    it "downloads every image's original in one zip, from a button that shows only when there is one" do
      get edit_manage_production_path(production, tab: 1)
      expect(response.body).not_to include("Download all originals")
      get manage_originals_production_visual_asset_path(production)
      expect(flash[:alert]).to eq("There are no images to download yet.")

      production.update!(wide_image: fixture_file_upload("test_image.png", "image/png"))
      ProductionAssets.new(production).store_file!(instagram, asset_image(1080, 1080, name: "ig.png"),
                                                   check: AssetCheck.call(instagram, asset_image(1080, 1080)))
      get edit_manage_production_path(production, tab: 1)
      expect(response.body).to include("Download all originals")

      get manage_originals_production_visual_asset_path(production)
      expect(response.media_type).to eq("application/zip")
      expect(response.headers["Content-Disposition"]).to include("Late Bloomers originals.zip")
      names = []
      Zip::InputStream.open(StringIO.new(response.body)) { |zip| while (entry = zip.get_next_entry) do names << entry.name end }
      expect(names).to contain_exactly("Wide image.png", "Instagram square.png")
    end

    it "makes an uploaded poster the primary one and keeps the one before it" do
      poster_spec = org.asset_specs.find_by(builtin: "poster")
      old = production.posters.create!(image: fixture_file_upload("test_image.png", "image/png"), is_primary: true)
      post manage_upload_production_visual_asset_path(production), params: { spec_id: poster_spec.id, file: asset_image(1080, 1440) }

      expect(response.parsed_body["ok"]).to be(true)
      expect(production.reload.primary_poster).not_to eq(old)
      expect(production.posters.count).to eq(2)
      expect(production.production_assets.find_by(asset_spec: poster_spec).last_change).to eq("replaced")
    end

    it "keeps an additional file of any size" do
      post manage_files_production_visual_asset_path(production), params: { name: "Postcard", file: asset_image(10, 30) }
      expect(flash[:notice]).to eq("Postcard added.")
      expect(production.production_assets.additional.last.name).to eq("Postcard")
    end

    it "sends the request to the people chosen, and tells people on the contract who have an account" do
      contractor_user = create(:user, password: password)
      contractor_person = create(:person, user: contractor_user, name: "Dana Whitfield", email: "dana@example.com")
      contractor = create(:contractor, organization: org, person: contractor_person, email: "dana@example.com", name: "Dana Whitfield")
      create(:contract, :active, organization: org, production: production, contractor: contractor, contractor_name: "Dana Whitfield", contractor_email: "dana@example.com")

      get edit_manage_production_path(production, tab: 1)
      expect(response.body).to include("Dana Whitfield", "Signs the contract")

      expect do
        post manage_request_production_visual_asset_path(production),
             params: { recipients: [ "dana@example.com" ], other_emails: "designer@example.com", subject: "Images for Late Bloomers",
                       message: "Hi Dana,\n\nWe need these.", allow_replace: "1", commit_action: "send" }
      end.to have_enqueued_mail(AppMailer, :send_template).twice

      expect(flash[:notice]).to eq("The request has been sent to dana@example.com and designer@example.com.")
      request = AssetRequest.current_for(production)
      expect(request.recipient_emails).to eq(%w[dana@example.com designer@example.com])
      expect(contractor_user.notifications.last.title).to eq("The Lantern Room requested images and details for Late Bloomers")
      expect(contractor_user.notifications.count).to eq(1)
      expect(contractor_user.notifications.last.path).to eq(my_contract_assets_path(Contract.last))
    end

    it "doesn't notify someone emailed who isn't on the contract" do
      designer = create(:user, email_address: "designer@example.com", password: password)
      create(:person, user: designer, name: "Sam Designer")
      expect do
        post manage_request_production_visual_asset_path(production),
             params: { other_emails: "Designer@example.com", subject: "Images", allow_replace: "1", commit_action: "send" }
      end.to have_enqueued_mail(AppMailer, :send_template).once
      expect(designer.notifications.count).to eq(0)
    end

    it "doesn't notify someone on the contract who wasn't emailed" do
      dana_user = create(:user, password: password)
      dana = create(:person, user: dana_user, name: "Dana Whitfield", email: "dana@example.com")
      contractor = create(:contractor, organization: org, person: dana, email: "dana@example.com", name: "Dana Whitfield")
      create(:contract, :active, organization: org, production: production, contractor: contractor, contractor_name: "Dana Whitfield", contractor_email: "dana@example.com")

      post manage_request_production_visual_asset_path(production), params: { other_emails: "designer@example.com", allow_replace: "1", commit_action: "send" }
      expect(dana_user.notifications.count).to eq(0)
    end

    it "notifies someone emailed on an in-house production's team, opening the link's page" do
      production.update!(production_type: "in_house")
      teammate = create(:user, email_address: "sam@example.com", password: password)
      create(:person, user: teammate, name: "Sam Teammate")
      create(:production_permission, user: teammate, production: production, role: "viewer")

      post manage_request_production_visual_asset_path(production), params: { other_emails: "sam@example.com", allow_replace: "1", commit_action: "send" }
      request = AssetRequest.current_for(production)
      expect(teammate.notifications.last.path).to eq(asset_request_path(token: request.token))
      expect(manager.notifications.count).to eq(0)

      expect { post manage_remind_production_visual_asset_path(production), params: { recipients: [ "sam@example.com" ] } }.not_to change(Notification, :count)
    end

    # Nothing is sent without being looked at first (Tim, 2026-11-19): the
    # reminder opens the request sheet in reminder mode.
    it "shows the reminder on the sheet first, and sends the words and people chosen there" do
      post manage_request_production_visual_asset_path(production),
           params: { other_emails: "designer@example.com, second@example.com", allow_replace: "1", commit_action: "send" }

      get edit_manage_production_path(production, tab: 1)
      expect(response.body).to include("Send a reminder for Late Bloomers", "Who gets the reminder", "What is still needed", "Send the reminder",
                                       "A reminder: Images and details needed for Late Bloomers", "designer@example.com", "second@example.com")
      expect(response.body).not_to include("Copy the link without emailing", "confirm-asset-reminder")

      expect do
        post manage_remind_production_visual_asset_path(production),
             params: { recipients: [ "designer@example.com" ], subject: "Still waiting on the poster", message: "Two items are left." }
      end.to have_enqueued_mail(AppMailer, :send_template).once.with(
        a_hash_including(params: a_hash_including(to: "designer@example.com",
                                                  variables: a_hash_including("subject" => "Still waiting on the poster", "message_html" => "<p>Two items are left.</p>")))
      )
      expect(flash[:notice]).to eq("A reminder has been sent to designer@example.com.")
      expect(AssetRequest.current_for(production).subject).to eq("Images and details needed for Late Bloomers")

      expect { post manage_remind_production_visual_asset_path(production) }.not_to have_enqueued_mail
      expect(flash[:alert]).to eq("Choose someone to send the reminder to.")
    end

    it "makes the link without emailing, makes a new one, and turns it off" do
      post manage_request_production_visual_asset_path(production), params: { commit_action: "copy", allow_replace: "1" }
      first = AssetRequest.current_for(production)
      expect(first).to be_open

      post manage_new_link_production_visual_asset_path(production)
      second = AssetRequest.current_for(production)
      expect(second.token).not_to eq(first.token)
      expect(first.reload).to be_turned_off

      post manage_turn_off_production_visual_asset_path(production)
      expect(AssetRequest.current_for(production)).to be_nil
    end

    it "refuses an address that isn't one" do
      post manage_request_production_visual_asset_path(production), params: { other_emails: "not an email", commit_action: "send" }
      expect(flash[:alert]).to eq(%("not an email" isn't an email address. Separate addresses with commas.))
      expect(AssetRequest.count).to eq(0)
    end
  end

  describe "the no-login page" do
    let!(:request_record) { production.asset_requests.create!(created_by: manager, allow_replace: false, sent_at: Time.current) }

    it "shows the list to anyone with the link, and offers a free account" do
      get asset_request_path(token: request_record.token)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Images and details for Late Bloomers", "0 of 5 done", "Instagram square", "Short blurb")
      expect(response.body).to include("Manage your production with CocoScout", "it stays free for up to six events a month")
      expect(response.body).not_to include("Built in")
    end

    it "takes a good file, refuses a bad one, and tells the managers once, a little later" do
      post asset_request_upload_path(token: request_record.token), params: { spec_id: instagram.id, file: asset_image(500, 500), uploader_name: "Dana Whitfield" }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["message"]).to include("too small")

      expect do
        post asset_request_upload_path(token: request_record.token), params: { spec_id: instagram.id, file: asset_image(1080, 1080), uploader_name: "Dana Whitfield" }
      end.to have_enqueued_job(AssetRequestActivityJob)
      body = response.parsed_body
      expect(body["ok"]).to be(true)
      expect(body["card_html"]).to include("Yours is 1080 × 1080.")
      expect(body["progress_html"]).to include("1 of 5 done")
      expect(production.production_assets.find_by(asset_spec: instagram).uploaded_by_name).to eq("Dana Whitfield")
    end

    it "saves written words as they're typed" do
      patch asset_request_text_path(token: request_record.token, spec_id: blurb.id), params: { text: "Six comics who started late." }, as: :json
      expect(response.parsed_body["ok"]).to be(true)
      expect(ProductionAssets.new(production).item(blurb).text).to eq("Six comics who started late.")

      description = org.asset_specs.find_by(builtin: "description")
      patch asset_request_text_path(token: request_record.token, spec_id: description.id), params: { text: "An hour of stand-up." }, as: :json
      expect(production.reload.description.to_plain_text).to eq("An hour of stand-up.")
    end

    it "won't replace what was there before when told not to, but lets them change their own" do
      wide = org.asset_specs.find_by(builtin: "wide")
      production.update!(wide_image: fixture_file_upload("test_image.png", "image/png"))
      post asset_request_upload_path(token: request_record.token), params: { spec_id: wide.id, file: asset_image(1280, 720) }
      expect(response.parsed_body["message"]).to eq("Wide image has already been added. Request a change from The Lantern Room if you need one.")

      post asset_request_upload_path(token: request_record.token), params: { spec_id: instagram.id, file: asset_image(1080, 1080) }
      post asset_request_upload_path(token: request_record.token), params: { spec_id: instagram.id, file: asset_image(1200, 1200) }
      expect(response.parsed_body["ok"]).to be(true)
    end

    it "says a turned-off link has been turned off, and takes nothing" do
      request_record.turn_off!
      get asset_request_path(token: request_record.token)
      expect(response).to have_http_status(:gone)
      expect(response.body).to include("This link has been turned off")

      post asset_request_upload_path(token: request_record.token), params: { spec_id: instagram.id, file: asset_image(1080, 1080) }
      expect(response).to have_http_status(:gone)
    end

    it "turns itself off after the production's last date" do
      show.update_column(:date_and_time, 2.days.ago)
      get asset_request_path(token: request_record.token)
      expect(response).to have_http_status(:gone)
      expect(response.body).to include("The last date of Late Bloomers has passed")
    end

    it "says an unknown link doesn't work" do
      get asset_request_path(token: "nothing-here")
      expect(response).to have_http_status(:not_found)
      expect(response.body).to include("This link doesn't work")
    end
  end

  describe "My Contracts, signed in" do
    let!(:dana) { create(:user, password: password) }
    let!(:dana_person) { create(:person, user: dana, name: "Dana Whitfield") }
    let!(:contractor) { create(:contractor, organization: org, person: dana_person) }
    let!(:contract) { create(:contract, :active, organization: org, production: production, contractor: contractor, contractor_name: "Dana Whitfield", contractor_email: contractor.email) }

    it "shows nothing until there is a request, then the same page with no link" do
      sign_in(dana)
      get my_contracts_path
      expect(response.body).not_to include("Add images and details")

      production.asset_requests.create!(created_by: manager)
      get my_contracts_path
      expect(response.body).to include("Images and details for The Lantern Room", "0 of 5 have been added.", "Add images and details")

      get my_contract_assets_path(contract)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Copy the link", "Instagram square")
      expect(response.body).not_to include("Manage your production with CocoScout")

      post my_contract_assets_upload_path(contract), params: { spec_id: instagram.id, file: asset_image(1080, 1080) }
      asset = production.production_assets.find_by(asset_spec: instagram)
      expect([ asset.uploaded_by_user, asset.uploaded_by_name ]).to eq([ dana, "Dana Whitfield" ])
    end

    it "isn't there for someone who isn't on the contract" do
      production.asset_requests.create!(created_by: manager)
      stranger = create(:user, password: password)
      create(:person, user: stranger)
      sign_in(stranger)
      get my_contract_assets_path(contract)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "the managers' notifications" do
    let!(:request_record) { production.asset_requests.create!(created_by: manager, sent_at: 1.hour.ago) }
    let(:assets) { ProductionAssets.new(production) }

    def arrive(spec, file, name:, replaced: false)
      assets.store_file!(spec, file, check: AssetCheck.call(spec, file), name: name, request: request_record)
      request_record.update_column(:last_activity_at, 11.minutes.ago)
    end

    it "folds what arrived into one notification, and only the run after the last change sends" do
      arrive(instagram, asset_image(1080, 1080), name: "Dana Whitfield")
      assets.store_text!(blurb, "Six comics.", name: "Dana Whitfield", request: request_record)
      request_record.update_column(:last_activity_at, 2.minutes.ago)

      expect { AssetRequestActivityJob.perform_now(request_record.id) }.not_to change(Notification, :count)

      request_record.update_column(:last_activity_at, 11.minutes.ago)
      expect { AssetRequestActivityJob.perform_now(request_record.id) }.to change(Notification, :count).by(1)
      expect(manager.notifications.last.title).to eq("Late Bloomers: Dana Whitfield added the Instagram square and the Short blurb. 2 of 5 received.")

      expect { AssetRequestActivityJob.perform_now(request_record.id) }.not_to change(Notification, :count)
    end

    it "says once when everything required has been added" do
      poster = org.asset_specs.find_by(builtin: "poster")
      wide = org.asset_specs.find_by(builtin: "wide")
      description = org.asset_specs.find_by(builtin: "description")
      arrive(poster, asset_image(1080, 1440), name: "Dana Whitfield")
      arrive(wide, asset_image(1280, 720), name: "Dana Whitfield")
      arrive(instagram, asset_image(1080, 1080), name: "Dana Whitfield")
      assets.store_text!(description, "An hour of stand-up.", name: "Dana Whitfield", request: request_record)
      assets.store_text!(blurb, "Six comics.", name: "Dana Whitfield", request: request_record)
      request_record.update_column(:last_activity_at, 11.minutes.ago)

      AssetRequestActivityJob.perform_now(request_record.id)
      expect(manager.notifications.last.title).to start_with("Late Bloomers: everything required has been added. Dana Whitfield added")
      expect(request_record.reload.completed_notified_at).to be_present
    end

    it "doesn't tell someone about their own change" do
      assets.store_file!(instagram, asset_image(1080, 1080), check: AssetCheck.call(instagram, asset_image(1080, 1080)), user: manager, name: "Tim Boisvert", request: request_record)
      request_record.update_column(:last_activity_at, 11.minutes.ago)

      expect { AssetRequestActivityJob.perform_now(request_record.id) }.not_to change(Notification, :count)
    end
  end
end
