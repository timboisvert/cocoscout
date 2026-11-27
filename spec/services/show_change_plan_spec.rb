# frozen_string_literal: true

require "rails_helper"

# What a date change touches and does (Cancel or move this date, Tim
# 2026-11-27), beyond the screens: every kind of buyer, the people waiting to
# cover, sign-ups, someone who can't be reached, a shift that also covers an
# event that isn't changing, a refund that fails, and a move that clashes.
RSpec.describe ShowChangePlan do
  include ActiveJob::TestHelper

  let(:owner) { create(:user) }
  let!(:org) { create(:organization, :pro, owner: owner, name: "The Parlor Room") }
  let(:production) { create(:production, organization: org, name: "The Friday Show") }
  let(:friday) { (Date.current + 14).next_occurring(:friday) }
  let!(:show) { create(:show, production: production, date_and_time: friday.in_time_zone.change(hour: 20), duration_minutes: 120) }
  let(:listing) { TicketListing.create!(show: show, status: "on_sale") }
  let!(:general) { listing.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 50) }

  before do
    allow(Stripe::Refund).to receive(:create).and_return(double("refund", id: "re_1"))
    allow(Stripe::PaymentIntent).to receive(:retrieve)
      .and_return(Stripe::PaymentIntent.construct_from(id: "pi_card", latest_charge: { balance_transaction: { fee: 220 } }))
  end

  def sold(count, name:, email:)
    order = TicketCheckout.start!(listing: listing, quantities: { general.id.to_s => count.to_s })
    order.update!(buyer_name: name, buyer_email: email)
    TicketOrderSettlement.settle!(order, payment_intent_id: "pi_#{name.parameterize}_#{order.id}")
    order.reload
  end

  def change_for(kind, shows, **attrs)
    org.date_changes.create!(kind: kind, show: shows.first, production: shows.first.production, created_by_user: owner,
                             scope: "this", show_ids: shows.map(&:id), **attrs)
  end

  def apply!(change)
    change.update!(status: "applying", steps: ShowChangePlan::Review.new(change, described_class.new(change)).planned_steps)
    perform_enqueued_jobs(only: ActionMailer::MailDeliveryJob) { ShowChangePlan::Apply.call(change.reload, by: owner) }
    change.reload
  end

  def mails_to(email) = ActionMailer::Base.deliveries.select { |m| m.to == [ email ] }
  def text(mail) = Nokogiri::HTML(mail.html_part&.body&.decoded || mail.body.decoded).text.squish

  describe "canceling, every kind of buyer" do
    it "refunds the card, marks cash refunded, returns pass credits, cancels comps, closes comp requests, and emails each buyer once" do
      sold(1, name: "Jordan Lee", email: "jordan@example.com")
      sold(1, name: "Jordan Lee", email: "jordan@example.com") # two orders, one buyer
      cash = TicketDoor.new(listing, owner).sell({ general.id.to_s => "1" }, kind: "cash", buyer_name: "Cash Buyer", buyer_email: "cash@example.com")
      comp = TicketComps.give!(listing, [ TicketComps::Guest.new(name: "Comp Guest", email: "comp@example.com", tier: general, quantity: 2) ], by: owner, email_them: false).sole

      pass = org.ticket_passes.create!(name: "Punch Card", kind: "punch_card", price_cents: 6_000, credits: 5, ends_on: 60.days.from_now.to_date,
                                       status: "on_sale", coverages_attributes: [ { production_id: production.id } ])
      purchase = TicketPassCredits.start!(pass: pass, quantity: 1)
      purchase.ticket_pass_holdings.update_all(holder_name: "Bella Swan", holder_email: "bella@example.com")
      perform_enqueued_jobs { TicketPurchaseSettlement.settle!(purchase.reload, payment_intent_id: "pi_card") }
      holding = purchase.ticket_pass_holdings.first.reload
      TicketPassCredits.use!(holding, listing: listing, people: 1)
      expect(holding.reload.credits_used).to eq(1)

      requester = create(:user)
      request = CompRequest.create!(organization: org, ticket_listing: listing, requested_by: requester, side: "team", quantity: 2, status: "waiting")
      ActionMailer::Base.deliveries.clear

      change = change_for("cancel", [ show ], choices: { "other_paid" => "1", "comps_email" => "1", "buyers_subject" => "{{show_title}} is off",
                                                         "buyers_body" => "Hi {{first_name}},\n\n{{what_happens}}" })
      plan = described_class.new(change)
      expect(plan.buyers.card.size).to eq(2)
      expect(plan.buyers.other.size).to eq(1)
      expect(plan.buyers.pass.size).to eq(1)
      expect(plan.buyers.comps.size).to eq(1)

      change = apply!(change)
      expect(show.reload).to be_canceled
      expect(listing.reload.status).to eq("canceled")
      orders = TicketOrder.where(ticket_listing: listing).where.not(id: [ cash.id, comp.id ])
      expect(orders.where(channel: "online").pluck(:status)).to all(eq("refunded"))
      expect(cash.reload.status).to eq("refunded")
      expect(comp.reload.tickets.map(&:status)).to all(satisfy { |s| !Ticket::SOLD_STATUSES.include?(s) })
      expect(holding.reload.credits_used).to eq(0)
      expect(request.reload.status).to eq("closed")

      jordan = mails_to("jordan@example.com")
      expect(jordan.size).to eq(1)
      expect(text(jordan.first)).to include("Hi Jordan,", "We've refunded")
      expect(text(mails_to("cash@example.com").sole)).to include("at the door", "Reply to this email")
      expect(text(mails_to("bella@example.com").sole)).to include("back on your pass")
      expect(text(mails_to("comp@example.com").sole)).to include("complimentary 2 tickets no longer work")
      expect(change.steps.map { |s| s["status"] }).to all(eq("done"))
      expect(BooksReconciliation.check(org)).to eq([])
    end

    it "keeps going when a card refund fails, and lists it to try again" do
      sold(1, name: "Ana Diaz", email: "ana@example.com")
      sold(1, name: "Ben Cole", email: "ben@example.com")
      calls = 0
      allow(Stripe::Refund).to receive(:create) do
        calls += 1
        raise Stripe::CardError.new("The card is closed.", nil) if calls == 1

        double("refund", id: "re_ok")
      end

      change = apply!(change_for("cancel", [ show ]))
      expect(change.open_problems.map { |p| p["kind"] }).to eq([ "refund" ])
      expect(change.open_problems.sole["label"]).to include("refund didn't go through")
      expect(change.step("refunds")["status"]).to eq("problem")
      expect(TicketOrder.where(ticket_listing: listing).pluck(:status)).to contain_exactly("refunded", "paid")
    end
  end

  describe "canceling, the people" do
    let(:role) { create(:role, production: production, name: "Host") }
    let(:priya) { create(:person, name: "Priya Shah", user: create(:user)) }
    let(:sam) { create(:person, name: "Sam Okafor", user: nil) }
    let(:cover) { create(:person, name: "Cara Cover", user: create(:user)) }

    it "closes can't-make-it requests and notifies their covers, flags someone who can't be reached, and cancels sign-ups" do
      org.people << [ priya, cover ]
      create(:show_person_role_assignment, show: show, assignable: priya, role: role)
      sam.update_columns(email: nil) # no login and no email: nobody can reach Sam through CocoScout
      create(:show_person_role_assignment, show: show, assignable: sam, role: role)
      vacancy = create(:role_vacancy, show: show, role: role, status: "open")
      create(:role_vacancy_invitation, role_vacancy: vacancy, person: cover)
      form = create(:sign_up_form, production: production)
      instance = create(:sign_up_form_instance, sign_up_form: form, show: show)
      slot = create(:sign_up_slot, sign_up_form: form, sign_up_form_instance: instance)
      registration = create(:sign_up_registration, sign_up_slot: slot, person: create(:person, name: "Opener One", user: create(:user)))

      change = apply!(change_for("cancel", [ show ]))
      expect(vacancy.reload.status).to eq("cancelled")
      expect(cover.user.notifications.pluck(:kind)).to include("date_change_cover_not_needed")
      expect(registration.reload.status).to eq("cancelled")
      expect(change.open_problems.map { |p| [ p["kind"], p["person_id"] ] }).to include([ "untold", sam.id ])
      expect(change.steps.map { |s| [ s["key"], s["status"] ] }).to all(satisfy { |_, st| st == "done" })
    end

    it "takes the date's own shift off but leaves one that also covers an event still on" do
      booth = create(:house_role, organization: org, name: "Booth", role_type: :show_specific)
      bar = create(:house_role, organization: org, name: "Bar", role_type: :house)
      late = create(:show, production: create(:production, organization: org, name: "Late Night Improv"),
                           location: show.location, date_and_time: show.date_and_time + 150.minutes, duration_minutes: 60)
      kai = create(:person, name: "Kai Turner", user: create(:user))
      marina = create(:person, name: "Marina Alvarez", user: create(:user))
      booth_shift = create(:shift, organization: org, house_role: booth, source: show, starts_at: show.date_and_time - 1.hour, ends_at: show.ends_at)
      bar_shift = create(:shift, organization: org, house_role: bar, source: show, starts_at: show.date_and_time - 90.minutes, ends_at: late.ends_at)
      bar_shift.shift_shows.create!(show: late)
      booth_shift.shift_assignments.create!(person: kai)
      bar_shift.shift_assignments.create!(person: marina)

      plan = described_class.new(change_for("cancel", [ show ]))
      expect(plan.staff.staying.map(&:person)).to eq([ marina ])
      expect(plan.staff.changing.map(&:person)).to eq([ kai ])

      apply!(change_for("cancel", [ show ]))
      expect(booth_shift.reload).to be_not_needed
      expect(bar_shift.reload).not_to be_not_needed
      expect(bar_shift.shift_assignments.active.map(&:person)).to eq([ marina ])
      expect(ShowChangeNotice.where(person: marina)).to be_empty
    end
  end

  describe "moving, with clashes" do
    it "opens a cast member's role and a staff member's shift for cover when they clash at the new time" do
      role = create(:role, production: production, name: "Host")
      priya = create(:person, name: "Priya Shah", user: create(:user))
      nora = create(:person, name: "Nora Patel", user: create(:user))
      org.people << [ priya, nora ]
      create(:show_person_role_assignment, show: show, assignable: priya, role: role)
      door = create(:house_role, organization: org, name: "Door", role_type: :show_specific)
      shift = create(:shift, organization: org, house_role: door, source: show, starts_at: show.date_and_time - 1.hour, ends_at: show.ends_at)
      shift.shift_assignments.create!(person: nora)

      saturday = show.date_and_time + 1.day
      other = create(:show, production: create(:production, organization: org, name: "Saturday Showcase"),
                            date_and_time: saturday, duration_minutes: 120)
      create(:show_person_role_assignment, show: other, assignable: priya)
      other_shift = create(:shift, organization: org, house_role: door, source: other, starts_at: saturday - 1.hour, ends_at: saturday + 2.hours)
      other_shift.shift_assignments.create!(person: nora)

      change = change_for("move", [ show ], move: { "date" => saturday.to_date.iso8601, "starts" => "20:00", "ends" => "22:00" })
      dest = ShowChangePlan::Moves.destinations(change).first
      expect(ShowChangePlan::Moves.cast_conflicts(dest, change).map { |c| c.person }).to eq([ priya ])
      plan = described_class.new(change)
      expect(ShowChangePlan::Moves.staff_conflicts(dest, change, plan.staff.changing).map(&:person)).to eq([ nora ])

      change.update!(choices: { "cast_conflicts" => { priya.id.to_s => "open" }, "staff_conflicts" => { "#{shift.id}-#{nora.id}" => "open" } })
      change = apply!(change)

      expect(show.reload.date_and_time).to eq(saturday)
      expect(RoleVacancy.where(show: show, role: role, vacated_by: priya, status: "open")).to exist
      expect(show.show_person_role_assignments.where(assignable: priya)).to be_empty
      expect(priya.user.notifications.pluck(:kind)).to include("date_change_role_opened")
      expect(shift.reload.starts_at).to eq(saturday - 1.hour)
      expect(shift.shift_assignments.active).to be_empty
      expect(nora.user.notifications.pluck(:kind)).to include("date_change_shift_opened")
      expect(change.steps.map { |s| s["status"] }).to all(eq("done"))
    end
  end

  describe "deleting" do
    it "lets go of what only pointed at the date, and refuses one with pay that went out" do
      spare = create(:show, production: production, date_and_time: show.date_and_time + 1.week)
      empty_shift = create(:shift, organization: org, house_role: create(:house_role, organization: org), source: spare,
                                   starts_at: spare.date_and_time - 1.hour, ends_at: spare.date_and_time + 2.hours)
      expect(ShowChangePlan::Delete.blockers([ spare ])).to eq([])
      ShowChangePlan::Delete.delete!([ spare ])
      expect(Show.exists?(spare.id)).to be false
      expect(Shift.exists?(empty_shift.id)).to be false

      sold(1, name: "Jordan Lee", email: "jordan@example.com")
      expect(ShowChangePlan::Delete.blockers([ show ])).to include("1 ticket sold to 1 buyer")
    end
  end
end
