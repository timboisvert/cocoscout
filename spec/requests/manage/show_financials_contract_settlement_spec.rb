# frozen_string_literal: true

require "rails_helper"

# Saving a show's numbers is what settles a contract that pays from ticket
# revenue. It has to reach the contract that booked THIS show — a production can
# carry several — and it has to work for a minus-fee deal, not just a split.
RSpec.describe "Manage::ShowFinancials settling a contract", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org, production_type: "third_party") }
  let!(:contract) do
    create(:contract, :active, organization: org, production: production, draft_data: {
             "payment_structure" => "flat_fee",
             "payment_config" => {
               "flat_fee_direction" => "ticket_revenue_minus_fee",
               "flat_fee_amount" => 300,
               "flat_fee_basis" => "per_show",
               "flat_fee_settlement" => "per_event"
             }
           })
  end
  # A second, newer contract on the same production: asking the production for
  # "its" contract would pick this one instead of the one that booked the show.
  let!(:newer_contract) { create(:contract, :active, organization: org, production: production) }
  let!(:rental) { create(:space_rental, contract: contract, starts_at: 2.days.ago.change(hour: 18)) }
  let!(:show) { create(:show, production: production, space_rental: rental, date_and_time: 2.days.ago.change(hour: 18)) }
  let!(:settlement) do
    create(:contract_payment, contract: contract, direction: "outgoing", show: show,
                              description: "Ticket revenue less $300.00 fee",
                              amount: 0, amount_tbd: true, due_date: 2.days.ago.to_date)
  end

  before do
    create(:show_financials, show: show, revenue_type: "ticket_sales")
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
  end

  it "bills the fee they didn't cover when the night sells under it" do
    patch manage_update_money_show_financials_path(show), params: {
      show_financials: { revenue_type: "ticket_sales", ticket_count: 10, ticket_revenue: 190, data_confirmed: true }
    }

    # The settlement itself turns around: one payment per show, facing whoever owes.
    expect(settlement.reload).to have_attributes(amount: 110.0, direction: "incoming", auto_shortfall: true, show_id: show.id)
    expect(settlement.collectable_online?).to be true
    expect(contract.contract_payments.count).to eq(1)
  end

  it "hands back the remainder when the night clears the fee" do
    patch manage_update_money_show_financials_path(show), params: {
      show_financials: { revenue_type: "ticket_sales", ticket_count: 40, ticket_revenue: 800, data_confirmed: true }
    }

    expect(settlement.reload).to have_attributes(amount: 500.0, direction: "outgoing", auto_shortfall: false)
    expect(contract.contract_payments.count).to eq(1)
  end
end
