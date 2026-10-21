# frozen_string_literal: true

require "rails_helper"

# V1.1 plan Phase 3 on a phone: the wizard shell, settings sections,
# template field chips, production edit sections, the casting table show
# pager, the question builder, Books and taxes.
RSpec.describe "Phase 3 pages on a phone", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org, name: "Variety Hour") }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  def doc
    expect(response).to have_http_status(:ok)
    Nokogiri::HTML(response.body)
  end

  it "says Step N of M with a bar on a wizard, keeping the circles for sm up" do
    get manage_shows_wizard_path(production)
    phone = doc.at_css("[data-wizard-phone-steps]")
    expect(phone["class"]).to include("sm:hidden")
    expect(phone.text.squish).to include("Step 1 of 5", "Type", "Next: Schedule")
    expect(phone.at_css("[role='progressbar']")["aria-valuenow"]).to eq("1")
    expect(doc.at_css("nav[aria-label='Progress']")["class"]).to include("hidden sm:block")
  end

  it "opens a settings page's sections from a sheet on a phone" do
    get manage_contract_settings_path
    row = doc.at_css("[data-settings-sections]")
    expect(row.at_css("button")["data-modal-id"]).to eq("settings-sections-sheet")
    expect(row.at_css("select")).to be_nil
    sheet = doc.at_css("#settings-sections-sheet")
    links = sheet.css("a")
    expect(links.size).to be > 1
    expect(links.find { |a| a["aria-current"] == "page" }).to be_present
  end

  it "puts Insert field chips above a template's editor" do
    get manage_new_staffing_agreement_template_path
    chips = doc.at_css("[data-controller='merge-field'] [data-merge-field-chips]")
    fields = chips.css("button").map { |b| b["data-field"] }
    expect(fields).to eq(StaffAgreementTemplate::MERGE_FIELDS.keys.map(&:to_s))
    expect(chips.at_css("button")["data-action"]).to eq("click->merge-field#insert")
    expect(chips.at_css("button").text).to eq("{{#{fields.first}}}")
  end

  it "drills into a production's sections on a phone, each with a way back" do
    get edit_manage_production_path(production)
    tabs = doc.at_css("[data-controller='tabs']")
    expect(tabs["data-tabs-drill-value"]).to eq("true")
    list = tabs.at_css("[data-production-edit-sections]")
    labels = list.css("button").map { |b| b.text.squish.delete_suffix(" Pro") }
    expect(labels).to eq([ "Basic Information", "Visual Assets", "Documents", "Production Team", "Agreement", "Public Listing", "Pay", "Tickets", "Services", "Danger Zone" ])
    panels = tabs.css("[data-tabs-target='panel']")
    expect(panels.size).to eq(labels.size)
    expect(panels.map { |p| p.at_css("[data-section-panel-header]").text.squish }).to eq(labels.map { |l| "Sections / #{l}" })
    expect(tabs.at_css("nav")["class"]).to include("hidden sm:flex")
  end

  describe "a casting table" do
    let!(:production) { create(:production, organization: org, name: "Variety Hour", casting_mode: :act_based) }
    let!(:magic) { create(:role, production: production, name: "Magic", position: 1, quantity: 1) }
    let!(:show) { create(:show, production: production, casting_enabled: true, date_and_time: 2.weeks.from_now.change(hour: 20)) }
    let!(:later) { create(:show, production: production, casting_enabled: true, date_and_time: 3.weeks.from_now.change(hour: 20)) }
    let!(:ada) { create(:person, name: "Ada Actor") }
    let!(:table) { CastingTable.create!(organization: org, created_by: owner, name: "Autumn run", status: "draft") }

    before do
      org.people << ada
      table.casting_table_productions.create!(production: production)
      table.casting_table_events.create!(show: show)
      table.casting_table_events.create!(show: later)
      table.casting_table_members.create!(memberable: ada)
    end

    it "pages one show at a time on a phone, each person a row that opens the picker" do
      get manage_casting_table_path(table)
      pager = doc.at_css("[data-controller='show-pager']")
      expect(pager["class"]).to include("md:hidden")
      pages = pager.css("[data-show-pager-target='page']")
      expect(pages.map { |p| p["data-show-page"] }).to eq([ show.id.to_s, later.id.to_s ])
      expect(pages.last["class"]).to include("hidden")
      expect(pager.at_css("[data-show-pager-target='label']").text).to eq("Show 1 of 2")
      row = pages.first.at_css("[data-member-row]")
      expect(row["data-action"]).to eq("click->casting-table#openRoleSelector")
      expect(row["data-member-key"]).to eq("Person_#{ada.id}")
      expect(row.text).to include("Ada Actor", "0 assignments on this table")
      expect(doc.at_css("[data-casting-table-grid]")["class"]).to include("max-md:hidden")
      expect(doc.at_css("#role-selector")["class"]).to include("max-sm:rounded-t-2xl")
    end
  end

  it "opens the question editor as a full-screen sheet and reorders by the handle only" do
    show = create(:show, production: production, date_and_time: 3.days.from_now)
    form = create(:sign_up_form, production: production, show: show)
    create(:question, questionable: form, text: "What will you perform?", question_type: "text", position: 1)
    get manage_edit_signups_form_path(production, form)
    sheet = doc.at_css("[data-question-sheet]")
    expect(sheet["class"]).to include("max-sm:min-h-[100dvh]")
    expect(sheet.at_css(".from-pink-500")).to be_present
    item = doc.at_css("[data-question-order-target='item']")
    expect(item["data-action"]).not_to include("touchstart")
    handle = item.at_css("[data-question-order-target='handle']")
    expect(handle["data-action"]).to include("touchstart->question-order#touchStart", "touchend->question-order#touchEnd")
  end

  it "lays out the 1099 row for a phone and shows the W-9 pill there" do
    staffer = create(:person, name: "Sam Staffer", email: "sam@example.com", user: create(:user))
    create(:organization_staff_member, organization: org, person: staffer, acknowledged_at: 1.week.ago)
    get manage_staffing_taxes_path
    expect(response).to have_http_status(:ok)
    body = Nokogiri::HTML(response.body)
    pill = body.css("span").find { |s| s.text.strip == "W-9 needed" }
    expect(pill["class"]).not_to include("hidden")
    row = body.at_css("[data-form-1099-row]")
    expect(row["class"]).to include("flex-wrap sm:flex-nowrap") if row
  end

  describe "Books" do
    let(:superadmin) { create(:user, email_address: "boisvert@gmail.com", password: password) }
    let(:listing) { create(:ticket_listing, organization: org) }
    let!(:general) { listing.ticket_tiers.create!(name: "General", price_cents: 2_000) }

    it "heads the entries with their month and draws the shows as cards on a phone" do
      create(:organization_role, :manager, user: superadmin, organization: org)
      post handle_signin_path, params: { email_address: superadmin.email_address, password: password }
      get manage_path
      order = TicketCheckout.start!(listing: listing, quantities: { general.id.to_s => "1" })
      TicketOrderSettlement.settle!(order)

      get manage_money_books_path(tab: "entries")
      expect(doc.at_css("[data-books-month]").text).to eq(Date.current.strftime("%B %Y"))

      get manage_money_books_path(tab: "shows")
      expect(doc.at_css("[data-books-show-cards]")["class"]).to include("sm:hidden")
      expect(doc.at_css("[data-books-show-table]")["class"]).to include("max-sm:hidden")
    end
  end
end
