# frozen_string_literal: true

require "rails_helper"

# A deal settled by the week has one settlement for all the week's shows. It
# used to get tied to whichever show asked for it first
# (Contract#find_payment_for_show wrote the show back "for future lookups"),
# and from then on its row read as that one night's: one night's ticket sales,
# a fee worked back from them ("Our fee −$70.00" on a $250 a show deal), and
# one show's fee held back for a week of three (contract 107, 2026-11-08).
RSpec.describe "Manage::Contracts weekly settlement rows", type: :request do
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
               "flat_fee_amount" => 250,
               "flat_fee_basis" => "per_show",
               "flat_fee_settlement" => "weekly"
             }
           })
  end

  # Thu, Fri and Sat of two weeks; "now" is the Sunday between them.
  let(:now) { Time.zone.local(2026, 11, 8, 12) }
  let(:week_one_days) { [ 5, 6, 7 ] }
  let(:week_two_days) { [ 12, 13, 14 ] }
  let!(:shows) do
    (week_one_days + week_two_days).index_with do |day|
      create(:show, production: production, date_and_time: Time.zone.local(2026, 11, day, 20))
    end
  end
  let!(:week_one) do
    create(:contract_payment, contract: contract, direction: "outgoing",
                              description: "Ticket revenue less $750.00 fee — week of Nov 2",
                              amount: 0, amount_tbd: true, due_date: Date.new(2026, 11, 7))
  end
  let!(:week_two) do
    create(:contract_payment, contract: contract, direction: "outgoing",
                              description: "Ticket revenue less $750.00 fee — week of Nov 9",
                              amount: 0, amount_tbd: true, due_date: Date.new(2026, 11, 14))
  end
  let!(:booth_techs) do
    shows.map do |day, show|
      create(:contract_payment, contract: contract, direction: "incoming", amount: 50, show: show,
                                description: "Booth Tech — Nov #{day}, 2026",
                                settlement_method: "payout_deduction", due_date: Date.new(2026, 11, day))
    end
  end

  def sell!(day, revenue)
    create(:show_financials, :complete, show: shows[day], ticket_revenue: revenue, other_revenue: 0.0)
    ContractPaymentSyncService.new(shows[day].reload).call
  end

  around { |example| travel_to(now) { example.run } }

  describe "which shows a week's settlement covers" do
    it "is never tied to the show that asked for it" do
      expect(contract.find_payment_for_show(shows[5])).to eq(week_one)
      expect(contract.find_payment_for_show(shows[13])).to eq(week_two)

      expect(week_one.reload.show_id).to be_nil
      expect(week_two.reload.show_id).to be_nil
    end

    context "when it already carries one night's link" do
      before do
        week_one.update_column(:show_id, shows[5].id)
        week_two.update_column(:show_id, shows[12].id)
      end

      it "still covers the whole week" do
        expect(contract.shows_for_payment(week_one.reload)).to match_array(shows.values_at(5, 6, 7))
        expect(contract.settlement_shows_for(week_two.reload)).to match_array(shows.values_at(12, 13, 14))
      end

      it "holds back the fee for every show in the week" do
        expect(week_two.reload.guaranteed_fee).to eq(750.0)
      end

      it "answers for a show by its week, not by the link" do
        # The first night moved into the second week: it's that week's now.
        shows[5].update_columns(date_and_time: Time.zone.local(2026, 11, 11, 20))

        expect(contract.reload.find_payment_for_show(shows[5].reload)).to eq(week_two)
      end

      it "says what it comes to now from the whole week's sales" do
        week_one_days.zip([ 400.0, 340.0, 340.0 ]).each { |day, revenue| sell!(day, revenue) }

        expect(week_one.reload.amount).to eq(330.0)
        expect(ContractPaymentSyncService.current_amount(week_one)).to eq(330.0)
      end

      it "waits for the last night of the week, not the first" do
        travel_to Time.zone.local(2026, 11, 13, 12)
        expect(week_two.reload).to be_settles_after_show

        travel_to Time.zone.local(2026, 11, 15, 12)
        expect(week_two.reload).not_to be_settles_after_show
      end
    end
  end

  describe "the settlement's name" do
    it "stays the whole week's, at the whole week's fee, after a shortfall turns back around" do
      # Two nights in and under their fee: they owe us, for now.
      sell!(5, 100.0)
      sell!(6, 100.0)
      expect(week_one.reload).to have_attributes(direction: "incoming", auto_shortfall: true)

      shows[5].show_financials.update!(ticket_revenue: 400.0)
      shows[6].show_financials.update!(ticket_revenue: 430.0)
      sell!(7, 430.0)

      expect(week_one.reload).to have_attributes(
        direction: "outgoing", amount: 510.0,
        description: "Ticket revenue less $750.00 fee — week of Nov 2"
      )
    end
  end

  describe "the rows on the contract page" do
    before do
      # The links production had, from before the fix.
      week_one.update_column(:show_id, shows[5].id)
      week_two.update_column(:show_id, shows[12].id)
      week_one_days.zip([ 400.0, 340.0, 340.0 ]).each { |day, revenue| sell!(day, revenue) }
      post handle_signin_path, params: { email_address: owner.email_address, password: password }
    end

    it "shows every night's sales and the fee for all three shows" do
      get manage_contract_path(contract)

      html = response.body.gsub(/\s+/, " ")
      expect(html).to match(%r{Ticket sales — Nov 5</dt> <dd[^>]*> \$400\.00 </dd>})
      expect(html).to match(%r{Ticket sales — Nov 6</dt> <dd[^>]*> \$340\.00 </dd>})
      expect(html).to match(%r{Ticket sales — Nov 7</dt> <dd[^>]*> \$340\.00 </dd>})
      [ 5, 6, 7 ].each do |day|
        expect(html).to match(%r{Our fee — Nov #{day}</dt> <dd[^>]*> −\$250\.00 </dd>})
        expect(html).to match(%r{Booth Tech — Nov #{day}, 2026</dt> <dd[^>]*>−\$50\.00</dd>})
      end
      expect(html).to match(%r{We pay them</dt> <dd[^>]*> \$180\.00 </dd>})
      expect(html).not_to include("−$70.00")
    end

    it "holds back three shows' fee for the week still to come" do
      get manage_contract_path(contract)

      html = response.body.gsub(/\s+/, " ")
      [ 12, 13, 14 ].each do |day|
        expect(html).to match(%r{Our fee — Nov #{day}</dt> <dd[^>]*>\$250\.00</dd>})
        expect(html).to match(%r{Booth Tech — Nov #{day}, 2026</dt> <dd[^>]*>\$50\.00</dd>})
      end
      expect(html).to match(%r{We keep</dt> <dd[^>]*>\$900\.00</dd>})
    end
  end

  # The week being played (Tim, 2026-11-13): one night in, sales under the
  # week's fee, so the settlement faces us for now. It's still the week's one
  # settlement: its booth tech rides it, the row says where it stands so far,
  # and nothing is collected or called overdue until the week is over.
  describe "a week in progress" do
    let(:now) { Time.zone.local(2026, 11, 13, 10) }

    before do
      sell!(12, 560.0)
      post handle_signin_path, params: { email_address: owner.email_address, password: password }
    end

    # The other nights' sheets open at nothing sold, as production had them:
    # the week's whole fee counts and the settlement turns to face us.
    def open_the_other_nights!
      sell!(13, 0.0)
      sell!(14, 0.0)
    end

    it "keeps the week's charges on its settlement while it faces us" do
      open_the_other_nights!
      expect(week_two.reload).to have_attributes(direction: "incoming", auto_shortfall: true, amount: 190.0)
      expect(contract.settlement_in_progress?(week_two)).to be(true)

      group = contract.reload.payment_schedule_groups.detect { |g| g[:payment].id == week_two.id }
      expect(group[:deductions].map(&:description)).to eq([ 12, 13, 14 ].map { |d| "Booth Tech — Nov #{d}, 2026" })
      expect(contract.payment_schedule_groups.map { |g| g[:payment].description }).not_to include(a_string_matching(/Booth Tech — Nov 1[234]/))
      expect(ContractSettlementWorking.for(week_two).net_cents).to eq(-34_000)
    end

    it "works out where the week stands, line by line" do
      working = ContractSettlementWorking.for(week_two.reload)

      expect(working.lines.map { |l| [ l.label, l.cents ] }).to eq([
        [ "Ticket sales — Nov 12", 56_000 ], [ "Ticket sales — Nov 13 (so far)", 0 ], [ "Ticket sales — Nov 14 (so far)", 0 ],
        [ "Our fee — Nov 12", -25_000 ], [ "Our fee — Nov 13", -25_000 ], [ "Our fee — Nov 14", -25_000 ],
        [ "Booth Tech — Nov 12, 2026", -5_000 ], [ "Booth Tech — Nov 13, 2026", -5_000 ], [ "Booth Tech — Nov 14, 2026", -5_000 ]
      ])
      expect(working.net_cents).to eq(-34_000)
      expect(working.when_words).to eq("after Sat, Nov 14's show, together with the week's other shows")
    end

    it "shows one row for the week on the contract page, with nothing to collect" do
      open_the_other_nights!
      get manage_contract_path(contract)

      doc = Nokogiri::HTML(response.body)
      row = doc.at_css("[data-settlement-so-far='#{week_two.id}']")
      text = row.text.squish
      expect(text).to include("$340.00", "they pay us, so far", "Settles after Nov 14", "Ticket sales — Nov 12", "$560.00",
                              "What they owe for services", "Booth Tech — Nov 13, 2026", "nothing is paid or collected before then")
      expect(row.text).not_to include("Collect", "overdue")
      expect(doc.css("[data-settlement-so-far]").size).to eq(1)
      expect(doc.text).not_to include("1 day overdue")
    end

    it "is an ordinary row again once the week is over" do
      travel_to Time.zone.local(2026, 11, 15, 12)
      expect(contract.settlement_in_progress?(week_two.reload)).to be(false)
    end

    it "says on the Settle up day when it's paid, with the calculation a click away" do
      org.update!(settle_up_starts_on: Date.new(2026, 11, 1))
      get manage_money_settle_up_day_path("2026-11-12")
      expect(response).to have_http_status(:ok)

      doc = Nokogiri::HTML(response.body)
      block = doc.at_css("#pay-#{shows[12].id}")
      expect(block.text.squish).to include("This contract settles weekly", "paid after Sat, Nov 14's show, together with the week's other shows",
                                           "View calculation", "They owe $340.00")
      expect(block.text).not_to include("View contract", "it's set on the contract")
      modal = doc.at_css("#contract-calculation-#{shows[12].id}")
      expect(modal.text.squish).to include("Ticket sales — Nov 12", "$560.00", "Our fee — Nov 14", "Booth Tech — Nov 14, 2026",
                                           "They pay us, so far", "$340.00", "Open the contract")
    end
  end
end
