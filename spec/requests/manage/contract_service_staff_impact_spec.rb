# frozen_string_literal: true

require "rails_helper"

# Taking a service off a contract's dates (Tim, 2026-11-10): when someone is
# scheduled to do that service there, the review step says who, the manager
# ticks that they come off the schedule, and applying takes those shifts off.
# A shift that's there for more than the removed service stays, with why.
# And a service can come off one date and every date after it.
RSpec.describe "Amend: removing a service people are scheduled for", type: :request do
  let(:password) { "Password123!" }
  let(:manager) { create(:user, password: password) }
  let(:org) { create(:organization, :pro, owner: manager) }
  let(:production) { create(:production, organization: org, production_type: "third_party") }
  let(:first_night) { 3.weeks.from_now.beginning_of_week.change(hour: 19) }
  let(:times) { [ first_night, first_night + 1.day, first_night + 2.days ] }
  let!(:booth_role) { create(:house_role, organization: org, name: "Booth Tech") }
  let!(:booth) do
    org.house_services.create!(name: "Booth Tech", default_price_cents: 2500, unit: "hourly", offered_on_contracts: true,
                               contract_booking_mode: "per_event").tap { |service| service.house_roles << booth_role }
  end
  let(:contract) do
    create(:contract, :active, organization: org, production: production, contractor_name: "Nuns4Fun", draft_data: {
      "services" => [ { "name" => "Booth Tech", "service_id" => booth.id, "per_event" => true, "unit" => "hourly", "unit_price" => 25.0,
                        "direction" => "incoming", "settlement" => "direct", "quantity" => 6.0,
                        "events" => times.map { |t| { "starts_at" => t.iso8601, "hours" => 2.0 } } } ]
    })
  end
  let(:shows) { [] }
  let(:ana) { create(:person, name: "Ana Ruiz") }
  let(:bo) { create(:person, name: "Bo Lee") }

  before do
    times.each do |t|
      rental = create(:space_rental, contract: contract, starts_at: t, ends_at: t + 3.hours)
      shows << create(:show, production: production, space_rental: rental, date_and_time: t, duration_minutes: 120)
    end
    contract.bill_services!(contract.draft_services)
    create(:organization_role, :manager, user: manager, organization: org)
    post handle_signin_path, params: { email_address: manager.email_address, password: password }
  end

  def booth_shift!(show, person: nil, told: true, **attrs)
    shift = create(:shift, organization: org, house_role: booth_role, source: show,
                           starts_at: show.date_and_time - 30.minutes, ends_at: show.date_and_time + 2.hours, **attrs)
    create(:shift_assignment, shift: shift, person: person, notified_at: (Time.current if told)) if person
    shift
  end

  def row(starts_at, on: true, **extra)
    { include: on ? "1" : "0", starts_at: starts_at.iso8601, hours: "2", unit_price: "25" }.merge(extra)
  end

  # Booth Tech on the dates given (indexes into times), off the rest.
  def booth_rows(on:, extra: {})
    { "0" => { include: "1", service_id: booth.id, name: "Booth Tech", unit: "hourly", per_event: "1", unit_price: "25",
               direction: "incoming", settlement: "direct",
               events: times.each_with_index.to_h { |t, j| [ j.to_s, row(t, on: on.include?(j), **(extra[j] || {})) ] } } }
  end

  def lines_with(on)
    contract.draft_services.map { |line| line.merge("events" => line["events"].values_at(*on)) }
  end

  def token = response.body[/name="staff_token" value="(\w+)"/, 1]

  describe "Change services and prices" do
    let!(:kept_shift) { booth_shift!(shows[0], person: bo) }
    let!(:shift) { booth_shift!(shows[1], person: ana) }

    before { post stage_amend_services_manage_contract_path(contract), params: { services: booth_rows(on: [ 0, 2 ]) } }

    it "names who's scheduled and waits for the box" do
      follow_redirect!
      html = CGI.unescapeHTML(response.body.gsub(/\s+/, " "))

      expect(html).to include("1 person scheduled for what you're removing", "Ana Ruiz", "Booth Tech, 6:30",
                              "Applying these changes takes this shift off the schedule.",
                              "told they're no longer scheduled the next time you send that week's updates from Scheduling",
                              "Take this person off the schedule.", 'data-controller="acknowledge-gate"', 'name="staff_acknowledged"')
      expect(html).to include(%(data-service-staff-date="#{times[1].to_date.iso8601}"))
      expect(html).not_to include("Bo Lee", "Staying on the schedule")
      expect(html).to match(/name="staff_acknowledged"[^>]*accent-pink-500/)
    end

    it "changes nothing until the box is ticked" do
      post apply_amend_services_manage_contract_path(contract)

      expect(response).to redirect_to(review_amend_services_manage_contract_path(contract))
      expect(flash[:alert]).to include("People are scheduled for a service this takes off.")
      expect(Shift.exists?(shift.id)).to be(true)
      expect(contract.reload.draft_services.first["events"].size).to eq(3)
    end

    it "sends the manager back when the list has changed since they read it" do
      follow_redirect!
      seen = token
      create(:shift_assignment, shift: shift, person: create(:person, name: "Cy Odom"), position: 2)

      post apply_amend_services_manage_contract_path(contract), params: { staff_acknowledged: "1", staff_token: seen }

      expect(response).to redirect_to(review_amend_services_manage_contract_path(contract))
      expect(Shift.exists?(shift.id)).to be(true)
    end

    it "takes the shift off the schedule once confirmed, and leaves the other dates' shifts" do
      follow_redirect!

      expect {
        post apply_amend_services_manage_contract_path(contract), params: { staff_acknowledged: "1", staff_token: token }
      }.to change { org.staff_schedule_removals.pending.count }.by(1)

      expect(response).to redirect_to(manage_contract_path(contract))
      expect(flash[:notice]).to include("Services and prices changed", "1 shift came off the schedule (1 person).")
      expect(Shift.exists?(shift.id)).to be(false)
      expect(Shift.exists?(kept_shift.id)).to be(true)
      removal = org.staff_schedule_removals.last
      expect([ removal.person_id, removal.shift_label, removal.shift_starts_at ]).to eq([ ana.id, "Booth Tech", shift.starts_at ])
      expect(contract.reload.draft_services.first["events"].map { |e| Time.zone.parse(e["starts_at"]) }).to eq([ times[0], times[2] ])
    end
  end

  describe "what comes off and what stays" do
    let(:impact) { ContractServiceStaffImpact.new(contract, lines_with([ 0, 2 ])) }

    it "takes an open shift off without asking, and tells nobody" do
      open_shift = booth_shift!(shows[1])

      expect(impact.people?).to be(false)
      expect(impact.shift_ids).to eq([ open_shift.id ])
      expect { impact.unschedule! }.not_to change(StaffScheduleRemoval, :count)
      expect(Shift.exists?(open_shift.id)).to be(false)
    end

    it "records no notice for someone who never knew about the shift" do
      booth_shift!(shows[1], person: ana, told: false)

      expect { impact.unschedule! }.not_to change(StaffScheduleRemoval, :count)
      expect(ShiftAssignment.where(person: ana)).to be_empty
    end

    it "keeps a shift that also covers another role" do
      shift = booth_shift!(shows[1], person: ana)
      shift.assign_additional_roles!([ create(:house_role, organization: org, name: "Bartender").id ])

      expect(impact.removals).to be_empty
      expect(impact.kept.map { |line| [ line.shift.id, line.reason ] }).to eq([ [ shift.id, "The shift is Booth Tech + Bartender, so it stays." ] ])
      expect(impact.people?).to be(false)
    end

    it "keeps a shift that's there for another show too" do
      shift = booth_shift!(shows[1], person: ana, ends_at: times[2] + 2.hours)
      shift.shows << shows[2]

      expect(impact.removals).to be_empty
      expect(impact.kept.first.reason).to eq("The shift is also there for the #{times[2].strftime('%a, %b %-d, %-l:%M %p')} show, so it stays.")
    end

    it "keeps a shift that has already started" do
      shift = booth_shift!(shows[1], person: ana)

      travel_to(shift.starts_at + 10.minutes) do
        expect(impact.removals).to be_empty
        expect(impact.kept.first.reason).to eq("It has already started, so it stays as it is.")
      end
    end

    it "leaves a show that asks for the service itself, and someone on another role" do
      booth_shift!(shows[1], person: ana)
      door = create(:shift, organization: org, house_role: create(:house_role, organization: org, name: "Door"), source: shows[1],
                            starts_at: times[1], ends_at: times[1] + 2.hours)
      create(:shift_assignment, shift: door, person: bo)
      expect(impact.removals.flat_map(&:people)).to eq([ ana ])

      ShowServices.change!(shows[1], booth, needed: true, people: 2)
      expect(ContractServiceStaffImpact.new(contract, lines_with([ 0, 2 ])).any?).to be(false)
    end

    it "leaves a date the same amendment removes to the date steps" do
      booth_shift!(shows[1], person: ana)

      expect(ContractServiceStaffImpact.new(contract, lines_with([ 0, 2 ]), skip_rental_ids: [ shows[1].space_rental_id ]).any?).to be(false)
    end
  end

  describe "the deal amendment's Services step" do
    let!(:shift) { booth_shift!(shows[2], person: ana) }

    before { post save_amend_ticketing_tech_manage_contract_path(contract), params: { services: booth_rows(on: [ 0, 1 ]) } }

    it "shows the same list on its review and won't apply without the box" do
      get amend_review_manage_contract_path(contract)
      html = CGI.unescapeHTML(response.body.gsub(/\s+/, " "))
      expect(html).to include("1 person scheduled for what you're removing", "Ana Ruiz", "Take this person off the schedule.")

      post apply_amendments_manage_contract_path(contract), params: { requires_signature: "0" }
      expect(response).to redirect_to(amend_review_manage_contract_path(contract))
      expect(Shift.exists?(shift.id)).to be(true)
      expect(contract.reload.draft_services.first["events"].size).to eq(3)
    end

    it "takes the shift off when the amendment is applied" do
      get amend_review_manage_contract_path(contract)

      expect {
        post apply_amendments_manage_contract_path(contract), params: { requires_signature: "0", staff_acknowledged: "1", staff_token: token }
      }.to change { org.staff_schedule_removals.pending.count }.by(1)

      expect(response).to redirect_to(manage_contract_path(contract))
      expect(Shift.exists?(shift.id)).to be(false)
      expect(contract.reload.draft_services.first["events"].size).to eq(2)
    end
  end

  describe "an amendment sent for a signature" do
    let!(:shift) { booth_shift!(shows[2], person: ana) }
    let(:staged) { { "services" => lines_with([ 0, 1 ]), "unschedule_shift_ids" => [ shift.id ] } }

    it "leaves the schedule alone while it only previews the document" do
      contract.preview_amendment(staged)

      expect(Shift.exists?(shift.id)).to be(true)
      expect(StaffScheduleRemoval.count).to eq(0)
    end

    it "takes the confirmed shifts off when it's applied on signing, and no others" do
      later = booth_shift!(shows[1], person: bo)

      contract.apply_amendment!(staged.merge("services" => lines_with([ 0 ])))

      expect(Shift.exists?(shift.id)).to be(false)
      expect(Shift.exists?(later.id)).to be(true)
    end
  end

  describe "this date and every date after it" do
    it "offers it in each date's Edit but the last" do
      get amend_services_manage_contract_path(contract)
      html = CGI.unescapeHTML(response.body.gsub(/\s+/, " "))

      expect(html).to include("Take Booth Tech off the 2 dates after this one too", "Take Booth Tech off the date after this one too",
                              'name="services[0][events][0][and_after]"', 'name="services[0][events][1][and_after]"')
      expect(html).not_to include('name="services[0][events][2][and_after]"')
      expect(html).to match(/name="services\[0\]\[events\]\[0\]\[and_after\]"[^>]*accent-pink-500/)
    end

    it "takes the service off that date and the later ones, and leaves the earlier one" do
      post stage_amend_services_manage_contract_path(contract),
           params: { services: booth_rows(on: [ 0, 2 ], extra: { 1 => { and_after: "1" } }) }
      follow_redirect!
      expect(response.body.gsub(/\s+/, " ")).to include("#{times[1].strftime('%b %-d')} and #{times[2].strftime('%b %-d')}: Booth Tech removed")

      post apply_amend_services_manage_contract_path(contract)
      expect(contract.reload.draft_services.first["events"].map { |e| Time.zone.parse(e["starts_at"]) }).to eq([ times[0] ])
    end

    it "never reaches a settled date" do
      contract.contract_payments.find_by(due_date: times[2].to_date).update!(status: "paid", paid_date: Date.current)

      post stage_amend_services_manage_contract_path(contract),
           params: { services: booth_rows(on: [ 0 ], extra: { 1 => { and_after: "1" } }) }
      post apply_amend_services_manage_contract_path(contract)

      expect(contract.reload.draft_services.first["events"].map { |e| Time.zone.parse(e["starts_at"]) }).to eq([ times[0], times[2] ])
    end
  end
end
