# frozen_string_literal: true

require "rails_helper"

# Books starts with its categories (Tim, 2026-11-02): a manager is sent to
# the setup until they've said "These are my categories"; the answers
# recommend a list; what they said no to leaves the pickers.
RSpec.describe "Books categories setup", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let(:org) { create(:organization, :pro, owner: owner, books_categories_set_up_at: nil) }

  def sign_in(user, role: :manager)
    if role == :viewer
      create(:organization_role, user: user, organization: org, company_role: "viewer").update!(module_grants: { "books" => "view" })
    else
      create(:organization_role, :manager, user: user, organization: org)
    end
    post handle_signin_path, params: { email_address: user.email_address, password: password }
    get manage_path
  end

  it "sends a manager to the setup from every Books page until the categories are acknowledged" do
    sign_in(owner)
    get manage_money_books_path
    expect(response).to redirect_to(manage_money_books_setup_path)
    get manage_money_bank_path
    expect(response).to redirect_to(manage_money_books_setup_path)
    get manage_money_statements_path
    expect(response).to redirect_to(manage_money_books_setup_path)

    get manage_money_index_path
    expect(response.body).to include("Start by setting up your categories", manage_money_books_setup_path)

    get manage_money_books_setup_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Set up your categories", "A venue", "A performing company", "We sell drinks or snacks", "Bar purchases", "These are my categories")
    # Before any answer, only the categories for everyone are recommended.
    expect(response.body).to include('value="spending:marketing" checked')
    expect(response.body).to include('value="spending:bar_purchases"  class')
  end

  it "saves the answers, hides what was said no to, adds the organization's own, and opens Books" do
    sign_in(owner)
    offered = BooksCategorySetup.new(org, profile: { "kind" => "venue", "bar" => "1" }).categories.select(&:recommended).map(&:id) - [ "spending:travel" ]
    patch manage_money_books_setup_path, params: { profile: { kind: "venue", bar: "1", nonprofit: "0" }, offered: offered,
                                                   custom: { expense: [ "Costume shop", "" ], income: [ "Raffle" ] } }
    expect(response).to redirect_to(manage_money_books_path)

    org.reload
    expect(org.books_categories_set_up_at).to be_present
    expect(org.books_categories_set_up_by).to eq(owner)
    expect(org.books_profile).to eq({ "kind" => "venue", "bar" => true })
    expect(org.books_nonprofit).to be(false)
    expect(org.money_categories_hidden).to include("spending:travel", "income:grant", "spending:merchandise_purchases")
    expect(org.money_categories_hidden).not_to include("spending:other", "income:other", "spending:bar_purchases", "spending:utilities")

    spending = MoneyCategories.spending_options(org)
    expect(spending.map(&:first)).to include("Bar purchases", "Utilities", "Costume shop", "Other")
    expect(spending.map(&:first)).not_to include("Travel", "Merchandise purchases")
    expect(spending.last.first).to eq("Other")
    expect(MoneyCategories.income_options(org).map(&:first)).to include("Raffle", "Bar and concessions")
    expect(MoneyCategories.income_options(org).map(&:first)).not_to include("Grant")
    # A row already in a hidden category keeps its label.
    expect(MoneyCategories.label_for("travel", :spending, organization: org)).to eq("Travel")

    get manage_money_books_path
    expect(response).to have_http_status(:ok)

    # Later, the same page saves without re-stamping and goes back to settings.
    stamp = org.books_categories_set_up_at
    get manage_money_books_setup_path
    expect(response.body).to include("Your categories", 'value="spending:travel"  class')
    patch manage_money_books_setup_path, params: { profile: { kind: "venue", bar: "1", nonprofit: "1" }, offered: offered + [ "spending:travel" ] }
    expect(response).to redirect_to(manage_money_settings_section_path(section: "books"))
    expect(org.reload.books_categories_set_up_at).to eq(stamp)
    expect(org.books_nonprofit).to be(true)
    expect(org.money_categories_hidden).not_to include("spending:travel")
    get manage_money_settings_section_path(section: "books")
    expect(response.body).to include("Change which are offered", "not offered")
  end

  it "asks for the kind of organization before anything is saved" do
    sign_in(owner)
    patch manage_money_books_setup_path, params: { profile: { bar: "1" }, offered: [ "spending:marketing" ] }
    expect(response).to redirect_to(manage_money_books_setup_path)
    expect(org.reload.books_categories_set_up_at).to be_nil
  end

  it "recommends by the answers" do
    school = BooksCategorySetup.new(org, profile: { "kind" => "school" }).recommendations
    expect(school.values_at("income:courses", "spending:instructors", "spending:utilities", "spending:marketing")).to all(be(true))
    expect(school.values_at("spending:bar_purchases", "income:grant", "spending:venue")).to all(be(false))

    company = BooksCategorySetup.new(org, profile: { "kind" => "company", "nonprofit" => "1", "merch" => "1" }).recommendations
    expect(company.values_at("spending:venue", "income:contract", "income:grant", "income:membership", "spending:fundraising", "income:merchandise", "spending:merchandise_purchases")).to all(be(true))
    expect(company.values_at("spending:utilities", "spending:bar_purchases", "spending:staff_pay")).to all(be(false))
  end

  it "doesn't ask someone who can only look, and keeps them off the setup" do
    sign_in(create(:user, password: password), role: :viewer)
    get manage_money_books_path
    expect(response).to have_http_status(:ok)
    get manage_money_books_setup_path
    expect(response).to redirect_to(manage_money_books_path)
  end
end
