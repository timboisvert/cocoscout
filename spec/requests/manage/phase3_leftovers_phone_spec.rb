# frozen_string_literal: true

require "rails_helper"

# The last three Phase 3 pieces (V1.1 plan §10): the Offset input for the
# days/hours/minutes triplets, the contract money step's payment lines and
# add-a-payment sheet, and the questionnaire responses table as cards on a
# phone.
RSpec.describe "Phase 3 leftovers on a phone", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org) }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  it "draws every cutoff triplet on sign-up settings with the Offset input, same names as before" do
    form = create(:sign_up_form, production: production, edit_cutoff_mode: "before_event", edit_cutoff_days: 1, edit_cutoff_hours: 2, edit_cutoff_minutes: 30)
    get manage_settings_signups_form_path(production, form)
    expect(response).to have_http_status(:ok)
    doc = Nokogiri::HTML(response.body)
    expect(doc.css("[data-offset-input]").size).to eq(4)
    before = doc.at_css("[data-cutoff-timing-target='editBeforeFields'] [data-offset-input]")
    expect(before.css("input").map { |i| i["name"] }).to eq(%w[sign_up_form[edit_cutoff_days] sign_up_form[edit_cutoff_hours] sign_up_form[edit_cutoff_minutes]])
    expect(before.css("input").map { |i| i["value"] }).to eq(%w[1 2 30])
    expect(before.at_css("input")["class"]).to include("min-h-[44px]")
    expect(before.at_css("input")["disabled"]).to be_nil
    expect(before.text).to include("days", "hours", "minutes", "before")
    after = doc.at_css("[data-cutoff-timing-target='editAfterFields'] [data-offset-input]")
    expect(after.css("input").map { |i| i["name"] }).to eq(%w[edit_cutoff_after_days edit_cutoff_after_hours edit_cutoff_after_minutes])
    expect(after.css("input").all? { |i| i["disabled"] }).to be(true)
    expect(doc.css("[data-cutoff-timing-target='cancelBeforeFields'] input").map { |i| i["name"] }).to include("sign_up_form[cancel_cutoff_minutes]")
  end

  it "draws the sign-up wizard's opens and closes offsets with it" do
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new) # the wizard keeps its state in the cache
    post manage_signups_forms_wizard_save_scope_path(production), params: { scope: "single_event" }
    get manage_signups_forms_wizard_schedule_path(production)
    expect(response).to have_http_status(:ok)
    doc = Nokogiri::HTML(response.body)
    names = doc.css("[data-offset-input] input").map { |i| i["name"] }
    expect(names).to include("opens_days_before", "opens_minutes_before", "closes_offset_days", "closes_minutes_offset")
    expect(doc.at_css("[data-offset-input] select[name='closes_before_after']")).to be_present
  end

  it "opens the contract money step's Add a payment as a sheet on a phone, with pink buttons and 44px removes" do
    contract = create(:contract, organization: org, contractor_name: "Rental Co", status: "draft")
    get manage_payments_contract_wizard_path(contract)
    expect(response).to have_http_status(:ok)
    doc = Nokogiri::HTML(response.body)
    sheet = doc.at_css("[data-payment-sheet]")
    panel = sheet.at_css(".rounded-t-2xl")
    expect(panel["class"]).to include("sm:rounded-xl", "max-h-[90dvh]")
    expect(sheet.at_css(".bg-gradient-to-r.from-pink-500")).to be_present
    expect(sheet.css("button").map(&:text).map(&:squish)).to include("Cancel", "Add payment")
    expect(sheet.css(".bg-red-600")).to be_empty
    expect(Rails.root.join("app/javascript/controllers/contract_payments_controller.js").read).to include("w-11 h-11 sm:w-8 sm:h-8", "data-payment-line")
  end

  it "shows a questionnaire's responses as cards on a phone and the table from md up" do
    questionnaire = create(:questionnaire, production: production)
    question = create(:question, questionable: questionnaire, text: "Favorite color?", question_type: "short_text")
    person = create(:person, name: "Rae Respondent")
    qr = QuestionnaireResponse.create!(questionnaire: questionnaire, respondent: person)
    QuestionnaireAnswer.create!(questionnaire_response: qr, question: question, value: "Blue")

    get manage_responses_table_contacts_questionnaire_path(questionnaire)
    expect(response).to have_http_status(:ok)
    doc = Nokogiri::HTML(response.body)
    card = doc.at_css("[data-response-card]")
    expect(card.text).to include("Rae Respondent", "Favorite color?", "Blue")
    expect(card.parent["class"]).to include("md:hidden")
    expect(doc.at_css("table").ancestors.map { |a| a["class"].to_s }.join(" ")).to include("hidden md:block")
  end
end
