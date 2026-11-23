# frozen_string_literal: true

require "rails_helper"

# What's left owed on a contract once no share can cover it (Tim, 2026-11-22):
# a box under Dates and money, not the first date it came from, with Collect
# and Change the amount (to $0 with a note when it won't be collected). The
# Message window can add the pay link.
RSpec.describe "Manage::ContractPayments change amount", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner, name: "Stars & Garters") }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org, production_type: "third_party") }
  let!(:contract) do
    create(:contract, :active, :revenue_share_per_event, organization: org, production: production, contractor_name: "Improvised Animorphs")
  end
  let!(:balance) do
    contract.contract_payments.create!(description: "Rehearsal balance — Sep 13, 2026", amount: 24, direction: "incoming",
                                       due_date: Date.new(2026, 9, 13), settlement_method: "payout_deduction")
  end

  around { |example| travel_to(Time.zone.local(2026, 11, 22, 12)) { example.run } }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  it "shows what's owed in its own box under the dates, with Collect and Change the amount" do
    get manage_contract_path(contract)

    html = CGI.unescapeHTML(response.body.gsub(/\s+/, " "))
    expect(html).to include('id="still-owed"', "Improvised Animorphs owes Stars & Garters $24.00",
                            "the rest of the rehearsal on Sep 13", "Change the amount", "change-amount-#{balance.id}")
    expect(html).not_to include("We paid them −", "We paid them -")
  end

  it "sets it to $0 with a note, and the box then says nothing is owed" do
    patch change_amount_manage_contract_contract_payment_path(contract, balance),
          params: { amount: "0.00", note: "We're not charging them for the last bit." },
          headers: { "HTTP_REFERER" => manage_contract_url(contract) }

    expect(response).to redirect_to(manage_contract_url(contract))
    expect(flash[:notice]).to eq("Set to $0. Nothing more is owed on it.")
    expect(balance.reload).to be_set_to_zero
    expect(balance.amount_changed_by).to eq(owner)

    get manage_contract_path(contract)
    html = CGI.unescapeHTML(response.body.gsub(/\s+/, " "))
    expect(html).to include("Nothing owed", "Not collected", "We're not charging them for the last bit.")
    expect(html).not_to include("owes Stars & Garters $24.00")
  end

  it "refuses a negative amount" do
    patch change_amount_manage_contract_contract_payment_path(contract, balance), params: { amount: "-1" },
                                                                                   headers: { "HTTP_REFERER" => manage_contract_url(contract) }
    expect(flash[:alert]).to include("must be $0.00 or more")
    expect(balance.reload.amount).to eq(24)
  end

  it "won't change money the organization owes" do
    share = contract.contract_payments.create!(description: "Their share", amount: 30, direction: "outgoing", due_date: Date.current)
    patch change_amount_manage_contract_contract_payment_path(contract, share), params: { amount: "0" },
                                                                                 headers: { "HTTP_REFERER" => manage_contract_url(contract) }
    expect(flash[:alert]).to include("can't be changed here")
    expect(share.reload.amount).to eq(30)
  end

  it "can't reach another organization's payment" do
    other = create(:contract, :active, organization: create(:organization, owner: create(:user)))
    foreign = other.contract_payments.create!(description: "Rent", amount: 100, direction: "incoming", due_date: Date.current)

    patch change_amount_manage_contract_contract_payment_path(other, foreign), params: { amount: "0" }
    expect(response).to have_http_status(:not_found)
    expect(foreign.reload.amount).to eq(100)
  end

  it "adds the pay link to a message when the manager ticks it" do
    owner.update!(default_person: create(:person, user: owner, name: "Tim Boisvert"))
    priya = create(:user)
    priya_person = create(:person, user: priya, name: "Priya Nair", email: priya.email_address).tap { |p| priya.update!(default_person: p) }
    ContractPerson.create!(contract: contract, person: priya_person, added_by: owner)

    post contract_thread_path(contract), params: { body: "Thanks for a great run!", pay_link_payment_ids: [ balance.id ] },
                                         headers: { "HTTP_REFERER" => manage_contract_url(contract) }

    expect(flash[:alert]).to be_nil
    body = ContractThread.root(contract).body.to_plain_text
    expect(body).to include("Thanks for a great run!", "Pay the $24.00 online:", "/pay/contract/#{balance.reload.payment_token}")
  end
end
