# frozen_string_literal: true

require "rails_helper"

# Moving a date used to move only the payments linked to its show. A fee nobody
# had linked stayed on the old date and went overdue there (Full Five Fridays:
# "Event 10 Fee" still due Nov 6 after the show moved to Nov 20; Tim,
# 2026-11-08), and the ones that did move kept the old date in their name.
RSpec.describe "Moving a contract date takes its payments along" do
  let(:org) { create(:organization, :pro) }
  let(:production) { create(:production, organization: org, production_type: "third_party") }
  let(:contract) do
    create(:contract, :active, organization: org, production: production, draft_data: {
             "payment_structure" => "per_event", "payment_config" => { "per_event_amount" => 100 }
           })
  end
  let(:nov_6) { Time.zone.local(2026, 11, 6, 21) }
  let(:dec_4) { Time.zone.local(2026, 12, 4, 21) }

  def book!(starts_at)
    rental = create(:space_rental, contract: contract, starts_at: starts_at, ends_at: starts_at + 150.minutes)
    show = create(:show, production: production, space_rental: rental, date_and_time: starts_at, duration_minutes: 150)
    [ rental, show ]
  end

  def fee!(description, due, **attrs)
    create(:contract_payment, contract: contract, direction: "incoming", amount: 100,
                              description: description, due_date: due, **attrs)
  end

  def move!(rental, to)
    ContractDateChanges.move!(contract: contract, rental: rental, starts_at: to, ends_at: to + 150.minutes)
  end

  let!(:november) { book!(nov_6) }
  let!(:december) { book!(dec_4) }

  it "moves a fee that was never linked to the show" do
    fee = fee!("Event 10 Fee", Date.new(2026, 11, 6))
    next_one = fee!("Event 11 Fee", Date.new(2026, 12, 4))

    move!(november.first, nov_6 + 14.days)

    expect(fee.reload.due_date).to eq(Date.new(2026, 11, 20))
    expect(fee.display_name).to eq("Event 10 Fee — Nov 20, 2026")
    expect(next_one.reload.due_date).to eq(Date.new(2026, 12, 4))
  end

  it "takes the date in a payment's name, and in what it folded in, with it" do
    share = fee!("Nov 6 — 50% to them", Date.new(2026, 11, 6), show: november.last, direction: "outgoing")
    booth = fee!("Booth Tech — Nov 6, 2026", Date.new(2026, 11, 6), amount: 50, settlement_method: "payout_deduction")
    folded = fee!("Event 10 Fee", Date.new(2026, 11, 6), amount: 150,
                  components: [ { "kind" => "service", "name" => "Booth Tech", "amount" => 50.0, "billed_for" => "2026-11-06" } ])

    move!(november.first, nov_6 - 1.day)

    expect(share.reload).to have_attributes(due_date: Date.new(2026, 11, 5), description: "Nov 5 — 50% to them")
    expect(booth.reload).to have_attributes(due_date: Date.new(2026, 11, 5), description: "Booth Tech — Nov 5, 2026")
    expect(folded.reload.components.first["billed_for"]).to eq("2026-11-05")
  end

  it "leaves a paid payment on the date it was settled" do
    paid = fee!("Event 10 Fee", Date.new(2026, 11, 6), status: "paid", paid_date: Date.new(2026, 11, 1))

    move!(november.first, nov_6 + 14.days)

    expect(paid.reload.due_date).to eq(Date.new(2026, 11, 6))
  end

  it "leaves a week's settlement where it is" do
    contract.update!(draft_data: {
                       "payment_structure" => "flat_fee",
                       "payment_config" => { "flat_fee_direction" => "ticket_revenue_minus_fee", "flat_fee_amount" => 250,
                                             "flat_fee_basis" => "per_show", "flat_fee_settlement" => "weekly" }
                     })
    week = fee!("Ticket revenue less $250.00 fee — week of Nov 2", Date.new(2026, 11, 6),
                direction: "outgoing", amount: 0, amount_tbd: true)

    move!(november.first, nov_6 - 1.day)

    expect(week.reload).to have_attributes(due_date: Date.new(2026, 11, 6),
                                           description: "Ticket revenue less $250.00 fee — week of Nov 2")
  end

  it "moves only the linked payments when the contract has another booking that day" do
    _matinee_rental, matinee = book!(Time.zone.local(2026, 11, 6, 15))
    linked = fee!("Event 10 Fee", Date.new(2026, 11, 6), show: november.last)
    unlinked = fee!("Event 10b Fee", Date.new(2026, 11, 6))
    matinee_fee = fee!("Matinee Fee", Date.new(2026, 11, 6), show: matinee)

    move!(november.first, nov_6 + 14.days)

    expect(linked.reload.due_date).to eq(Date.new(2026, 11, 20))
    expect(unlinked.reload.due_date).to eq(Date.new(2026, 11, 6))
    expect(matinee_fee.reload.due_date).to eq(Date.new(2026, 11, 6))
  end

  describe ContractPaymentDateRepair do
    # The state the old move left: the night is somewhere else, its payment isn't.
    def move_the_old_way!(rental, show, to)
      rental.update!(starts_at: to, ends_at: to + 150.minutes)
      show.update!(date_and_time: to)
      contract.contract_payments.status_pending.where(show_id: show.id).find_each { |p| p.update!(due_date: to.to_date) }
    end

    it "puts each payment left behind on the night it belongs to" do
      event_10 = fee!("Event 10 Fee", Date.new(2026, 11, 6))
      event_11 = fee!("Event 11 Fee", Date.new(2026, 12, 4))
      move_the_old_way!(*november, nov_6 + 14.days)
      move_the_old_way!(*december, dec_4 + 14.days)

      result = described_class.run!

      expect(event_10.reload.due_date).to eq(Date.new(2026, 11, 20))
      expect(event_11.reload.due_date).to eq(Date.new(2026, 12, 18))
      expect(result.changes.map(&:payment_id)).to contain_exactly(event_10.id, event_11.id)
      expect(described_class.run!.changes).to be_empty
    end

    it "renames a payment that moved with its show but kept the old date" do
      share = fee!("Nov 6 — 50% to them", Date.new(2026, 11, 6), show: november.last, direction: "outgoing")
      booth = fee!("Booth Tech — Nov 6, 2026", Date.new(2026, 11, 6), amount: 50)
      move_the_old_way!(*november, nov_6 - 1.day)
      # The old move did take the service's own list of nights along.
      contract.update!(draft_data: contract.draft_data.merge(
        "services" => [ { "name" => "Booth Tech", "per_event" => true,
                          "events" => [ { "starts_at" => (nov_6 - 1.day).iso8601, "hours" => 2 } ] } ]
      ))

      described_class.run!

      expect(share.reload).to have_attributes(due_date: Date.new(2026, 11, 5), description: "Nov 5 — 50% to them")
      expect(booth.reload).to have_attributes(due_date: Date.new(2026, 11, 5), description: "Booth Tech — Nov 5, 2026")
    end

    it "changes nothing on a dry run" do
      fee = fee!("Event 10 Fee", Date.new(2026, 11, 6))
      fee!("Event 11 Fee", Date.new(2026, 12, 4))
      move_the_old_way!(*november, nov_6 + 14.days)

      result = described_class.run!(dry_run: true)

      expect(result.changes.size).to eq(1)
      expect(fee.reload.due_date).to eq(Date.new(2026, 11, 6))
    end

    it "never takes a deposit due ahead of the night for a leftover" do
      deposit = fee!("Deposit", Date.new(2026, 10, 1))
      contract.space_rentals.where.not(id: november.first.id).destroy_all

      result = described_class.run!

      expect(deposit.reload.due_date).to eq(Date.new(2026, 10, 1))
      expect(result.changes).to be_empty
      expect(result.unplaced).to be_empty
    end

    it "leaves alone a night's payment with nowhere certain to go, and says so" do
      stray = fee!("Event 10 Fee", Date.new(2026, 11, 8))
      fee!("Event 9 Fee", Date.new(2026, 11, 6))
      fee!("Event 11 Fee", Date.new(2026, 12, 4))

      result = described_class.run!

      expect(stray.reload.due_date).to eq(Date.new(2026, 11, 8))
      expect(result.changes).to be_empty
      expect(result.unplaced.size).to eq(1)
    end

    it "never touches a paid payment or one in a payout run" do
      paid = fee!("Event 10 Fee", Date.new(2026, 11, 6), status: "paid", paid_date: Date.new(2026, 11, 1))
      move_the_old_way!(*november, nov_6 + 14.days)

      expect(described_class.run!.changes).to be_empty
      expect(paid.reload.due_date).to eq(Date.new(2026, 11, 6))
    end
  end
end
