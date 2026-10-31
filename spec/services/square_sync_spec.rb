# frozen_string_literal: true

require "rails_helper"

# Square into RegisterDays (plan §9.3): orders and payments grouped into
# business days by the organization's Settle up setting, sales by our
# category, tips, tax, refunds, fees and the net.
RSpec.describe SquareSync do
  let(:owner) { create(:user) }
  let(:org) { create(:organization, :pro, owner: owner, settlement_day_mode: "smart", settlement_day_starts_at: 5) }
  let!(:lodge) { create(:location, organization: org, name: "Lincoln Lodge") }
  let(:integration) do
    org.integrations.create!(provider: "square", tokens: { "access_token" => "tok", "expires_at" => 30.days.from_now.iso8601 }, status: "connected",
                             settings: { "locations" => [ { "id" => "L1", "name" => "The bar" }, { "id" => "L2", "name" => "Catering" } ],
                                         "location_map" => { "L1" => lodge.id.to_s, "L2" => Integration::SKIP },
                                         "category_map" => { "C_BEER" => "bar", "C_TEES" => "merchandise" } })
  end
  let(:api) { instance_double(SquareApi) }

  before do
    allow(SquareApi).to receive(:new).and_return(api)
    allow(api).to receive(:catalog).and_return([
      { "type" => "ITEM", "id" => "I_BEER", "item_data" => { "name" => "Beer", "reporting_category" => { "id" => "C_BEER" }, "variations" => [ { "id" => "V_BEER" } ] } },
      { "type" => "ITEM", "id" => "I_TEE", "item_data" => { "name" => "T-shirt", "category_id" => "C_TEES", "variations" => [ { "id" => "V_TEE" } ] } },
      { "type" => "CATEGORY", "id" => "C_BEER", "category_data" => { "name" => "Beer" } },
      { "type" => "CATEGORY", "id" => "C_TEES", "category_data" => { "name" => "T-shirts" } }
    ])
    allow(api).to receive(:locations).and_return([ { "id" => "L1", "name" => "The bar" } ])
    allow(api).to receive(:merchant).and_return({ "business_name" => "Stars and Garters LLC" })
  end

  it "reads a night's orders into one business day, a 12:15 am round included, and skips a location that is not ours" do
    friday = Date.new(2026, 10, 30)
    orders = [
      { "closed_at" => Time.zone.local(2026, 10, 30, 21, 10).iso8601, "total_tax_money" => { "amount" => 120 }, "total_tip_money" => { "amount" => 300 },
        "line_items" => [ { "catalog_object_id" => "V_BEER", "gross_sales_money" => { "amount" => 1_200 }, "total_discount_money" => { "amount" => 200 } } ] },
      { "closed_at" => Time.zone.local(2026, 10, 31, 0, 15).iso8601, "total_tax_money" => { "amount" => 250 }, "total_tip_money" => { "amount" => 500 },
        "line_items" => [ { "catalog_object_id" => "V_TEE", "gross_sales_money" => { "amount" => 2_500 } }, { "catalog_object_id" => "V_NEW", "gross_sales_money" => { "amount" => 400 } } ],
        "return_amounts" => { "total_money" => { "amount" => 100 } } }
    ]
    expect(api).to receive(:orders).with("L1", from: anything, to: anything).and_return(orders)
    expect(api).not_to receive(:orders).with("L2", anything)
    allow(api).to receive(:payments).with("L1", from: anything, to: anything).and_return([
      { "created_at" => Time.zone.local(2026, 10, 30, 21, 11).iso8601, "processing_fee" => [ { "amount_money" => { "amount" => 60 } } ] },
      { "created_at" => Time.zone.local(2026, 10, 31, 0, 16).iso8601, "processing_fee" => [ { "amount_money" => { "amount" => 90 } } ] }
    ])

    pull = described_class.pull!(integration, from: friday, to: friday, trigger: "morning")
    expect(pull).to be_done
    expect(pull.orders_count).to eq(2)

    day = integration.register_days.find_by!(business_date: friday)
    expect(day.location).to eq(lodge)
    expect(day.sales_by_category).to eq({ "bar" => 1_000, "merchandise" => 2_500, "other" => 400 })
    expect(day.gross_cents).to eq(3_900)
    expect(day.tax_cents).to eq(370)
    expect(day.tips_cents).to eq(800)
    expect(day.refunds_cents).to eq(100)
    expect(day.fees_cents).to eq(150)
    expect(day.net_cents).to eq(3_900 + 370 + 800 - 100 - 150)
    expect(integration.reload.last_synced_at).to be_present
    expect(integration.external_categories.map { |c| c["name"] }).to eq([ "Beer", "T-shirts" ])
  end

  it "logs a pull that did not finish and marks the integration" do
    allow(api).to receive(:orders).and_raise(SquareApi::Error, "Square was slow")
    pull = described_class.pull!(integration, from: Date.new(2026, 10, 30), to: Date.new(2026, 10, 30), trigger: "manual")
    expect(pull).to be_failed
    expect(pull.error).to eq("Square was slow")
    expect(integration.reload.status).to eq("error")
    expect(integration.last_error).to eq("Square was slow")
  end
end
