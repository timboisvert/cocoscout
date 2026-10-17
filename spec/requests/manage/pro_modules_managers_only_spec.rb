# frozen_string_literal: true

require "rails_helper"

# The Pro modules are the organization's managers' (Tim, 2026-10-06). A
# producer on a production's team keeps the free modules: shows, casting,
# sign-ups; never Money, Contracts, Reports, Staffing or Ticketing.
RSpec.describe "Pro modules are for managers", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, email_address: "owner@sg.example", password: password) }
  let(:org) { create(:organization, :pro, name: "Stars & Garters", owner: owner) }
  let(:production) { create(:production, organization: org, name: "Boylesque") }
  let!(:show) { create(:show, production: production, date_and_time: 6.days.from_now.change(hour: 19)) }
  let(:producer) { create(:user, email_address: "producer@sg.example", password: password) }

  before do
    create(:organization_role, :manager, user: owner, organization: org)
    create(:organization_role, user: producer, organization: org, company_role: "member")
    ProductionPermission.create!(user: producer, production: production, role: "manager")
    TicketsAnswer.apply!(production, mode: "cocoscout", tiers: [ { "name" => "General", "price" => "20", "seats" => "60" } ])
  end

  def sign_in(user)
    post handle_signin_path, params: { email_address: user.email_address, password: password }
    post set_organization_path(id: org.id)
  end

  it "keeps a producer out of Money, Contracts, Reports, Staffing and Ticketing, and off the Pro nav" do
    sign_in(producer)
    get manage_production_show_path(production, show)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Tickets sold")
    expect(response.body).not_to include(manage_money_show_financials_path(show), manage_money_index_path, manage_contracts_path, manage_reports_path, manage_staffing_index_path, manage_ticketing_path)
    expect(response.body).not_to include('tracking-wider text-gray-400">Pro</div>') # no Pro heading in the nav either

    [ manage_money_index_path, manage_money_show_financials_path(show), manage_contracts_path, manage_reports_path,
      manage_money_production_advances_path(production), manage_staffing_index_path, manage_ticketing_path ].each do |path|
      get path
      expect(response).to redirect_to(manage_path), "expected #{path} to send a producer home"
      expect(flash[:notice]).to eq("That part of CocoScout is for your organization's managers.")
    end
  end

  it "keeps a producer out of the Pro actions on the production page (pay, agreements)" do
    template = AgreementTemplate.create!(organization: org, name: "House rules", content: "<p>Be kind</p>")
    sign_in(producer)

    patch update_pay_manage_production_path(production), params: { performers_paid: "0" }
    expect(response).to redirect_to(manage_path)
    expect(production.reload.pays_performers?).to be(true)

    get agreement_status_manage_production_path(production)
    expect(response).to redirect_to(manage_path)

    post send_agreement_reminders_manage_production_path(production)
    expect(response).to redirect_to(manage_path)

    patch manage_production_path(production),
          params: { production: { name: "Boylesque!", agreement_template_id: template.id, agreement_required: "1" } }
    production.reload
    expect(production.name).to eq("Boylesque!") # the free settings still save
    expect(production.agreement_template_id).to be_nil
    expect(production.agreement_required).to be_falsey

    get edit_manage_production_path(production)
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(manage_money_payout_calculation_wizard_start_path(production_id: production.id))
    expect(response.body).not_to include(manage_agreement_templates_path)
  end

  # Tim, 2026-10-17: archiving and deleting a production is the organization's
  # managers' business; a production team member gets no Danger Zone tab, and
  # the productions list without the organization's filters.
  it "keeps a producer out of the Danger Zone and off the productions filters" do
    sign_in(producer)
    get edit_manage_production_path(production)
    expect(response.body).not_to include("Danger Zone")
    expect(response.body.scan('data-tabs-target="tab"').size).to eq(response.body.scan('data-tabs-target="panel"').size)

    delete manage_production_path(production)
    expect(response).to redirect_to(manage_path)
    expect(Production.exists?(production.id)).to be(true)
    get confirm_delete_manage_production_path(production)
    expect(response).to redirect_to(manage_path)

    get manage_productions_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(production.name)
    expect(response.body).not_to include(">First-party<", ">Contract<", ">Course<")

    sign_in(owner)
    get edit_manage_production_path(production)
    expect(response.body).to include("Danger Zone")
    get manage_productions_path
    expect(response.body).to include(">First-party<")
  end

  it "keeps a producer from taking a date off CocoScout sales on the show page" do
    sign_in(producer)

    patch manage_update_show_path(production, show),
          params: { show: { secondary_name: "Late show", tickets_override: "1", tickets_mode: "none" } }
    show.reload
    expect(show.secondary_name).to eq("Late show") # the free settings still save
    expect(show.tickets_mode).to be_nil
    expect(production.production_ticketing.reload.excluded_show_ids).not_to include(show.id)

    get manage_edit_show_path(production, show)
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Set tickets for this date only")
  end

  # Email bodies carry contract signing and pay links; the page has no
  # links into it any more, but any role could open it by id.
  it "keeps a producer out of the organization's sent email" do
    log = create(:email_log, organization: org, user: owner, subject: "Sign your contract")
    sign_in(producer)

    get manage_contacts_email_path(log)
    expect(response).to redirect_to(manage_path)
  end

  it "lets a manager in everywhere" do
    sign_in(owner)
    [ manage_money_index_path, manage_money_show_financials_path(show), manage_contracts_path, manage_reports_path, manage_ticketing_path ].each do |path|
      get path
      expect(response).to have_http_status(:ok), "expected #{path} to open for a manager"
    end
    get manage_production_show_path(production, show)
    expect(response.body).to include(manage_money_show_financials_path(show), manage_ticket_listing_path(show.ticket_listing))
  end
end
