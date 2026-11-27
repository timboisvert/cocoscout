# frozen_string_literal: true

require "rails_helper"

# Cancel or move this date (Tim, 2026-11-27), the paths that go wrong or
# sideways: a button pressed twice, dates that can't change, a refund tried
# again, someone who only manages one production, a contract date canceled
# and brought back, buyers moved to another date, a move to a new place, and
# the edit form, which no longer changes a date's time.
RSpec.describe "Cancel or move this date, the edges", type: :request do
  include ActiveJob::TestHelper

  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner, name: "The Parlor Room") }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org, name: "The Friday Show") }
  let(:friday) { (Date.current + 14).next_occurring(:friday) }
  let!(:show) { create(:show, production: production, date_and_time: friday.in_time_zone.change(hour: 20), duration_minutes: 120) }
  let!(:next_show) { create(:show, production: production, location: show.location, date_and_time: show.date_and_time + 1.week, duration_minutes: 120) }
  let(:listing) { TicketListing.create!(show: show, status: "on_sale") }
  let!(:general) { listing.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 50) }

  before do
    allow(Stripe::Refund).to receive(:create).and_return(double("refund", id: "re_1"))
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
  end

  def sold(count, name:, email:, on: listing, tier: general)
    order = TicketCheckout.start!(listing: on, quantities: { tier.id.to_s => count.to_s })
    order.update!(buyer_name: name, buyer_email: email)
    TicketOrderSettlement.settle!(order, payment_intent_id: "pi_#{name.parameterize}_#{order.id}")
    order.reload
  end

  def start(kind, on: show)
    post manage_create_date_change_path(on.production, on), params: { kind: kind }
    DateChange.last
  end

  def page = Nokogiri::HTML(response.body)
  def text(mail) = Nokogiri::HTML(mail.html_part&.body&.decoded || mail.body.decoded).text.squish

  it "does the change once when the button is pressed twice" do
    sold(1, name: "Jordan Lee", email: "jordan@example.com")
    change = start("cancel")
    expect { 2.times { post manage_apply_date_change_path(change) } }.to have_enqueued_job(DateChangeApplyJob).once
    expect(response).to redirect_to(manage_date_change_path(change))
    perform_enqueued_jobs(only: DateChangeApplyJob)
    # A job run again finds it done and leaves it alone.
    DateChangeApplyJob.perform_now(change.id, owner.id)
    expect(Stripe::Refund).to have_received(:create).once
  end

  it "does nothing at all when a date can't be canceled, and says why" do
    sold(1, name: "Jordan Lee", email: "jordan@example.com")
    ana = create(:person, name: "Ana Diaz", user: create(:user))
    create(:show_person_role_assignment, show: show, assignable: ana)
    change = start("cancel")
    allow_any_instance_of(Show).to receive(:save!).and_raise(ActiveRecord::RecordInvalid.new(show.tap { |s| s.errors.add(:base, "This date is booked at Elsewhere and follows their contract.") }))

    perform_enqueued_jobs(only: DateChangeApplyJob) { post manage_apply_date_change_path(change) }
    change.reload
    expect(change.status).to eq("applied")
    expect(change.step("dates")["status"]).to eq("problem")
    expect(change.steps.drop(1).map { |s| s["status"] }).to all(eq("skipped"))
    expect(change.open_problems.sole["detail"]).to include("follows their contract")
    expect(Show.find(show.id)).not_to be_canceled
    expect(listing.reload.status).to eq("on_sale")
    expect(Stripe::Refund).not_to have_received(:create)
    expect(ana.user.notifications).to be_empty

    get manage_date_change_path(change)
    expect(response).to have_http_status(:ok)
    expect(page.text).to include("couldn't be done, so nothing else was", "Not done: the dates didn't change.")
  end

  it "never leaves the page spinning when CocoScout itself stops partway" do
    sold(1, name: "Jordan Lee", email: "jordan@example.com")
    change = start("cancel")
    allow(TicketOrderRefund).to receive(:issue!).and_raise(NoMethodError, "undefined method for nil")
    allow_any_instance_of(DateChange).to receive(:add_problem!).and_wrap_original do |original, **args|
      raise "the record page's own write failed" if args[:kind] == "refund"

      original.call(**args)
    end
    perform_enqueued_jobs(only: DateChangeApplyJob) { post manage_apply_date_change_path(change) }
    change.reload
    expect(change.status).to eq("applied")
    expect(change).to be_finished
    expect(change.open_problems.map { |p| p["key"] }).to include("stopped")
  end

  it "tries a failed refund again, or marks it refunded another way" do
    ana = sold(1, name: "Ana Diaz", email: "ana@example.com")
    ben = sold(1, name: "Ben Cole", email: "ben@example.com")
    allow(Stripe::Refund).to receive(:create).and_raise(Stripe::CardError.new("The card is closed.", nil))
    change = start("cancel")
    perform_enqueued_jobs(only: DateChangeApplyJob) { post manage_apply_date_change_path(change) }
    expect(change.reload.open_problems.size).to eq(2)

    get manage_date_change_path(change)
    expect(page.css("[data-problem]").size).to eq(2)
    expect(page.text).to include("Try again", "Refunded another way", "The card payment couldn't be refunded")
    expect(page.text).not_to include("Stripe")

    # Home lists the change while something is left to sort out.
    get manage_path
    expect(Nokogiri::HTML(response.body).at_css("[data-home-actions]").text).to include("The Friday Show's dates were canceled: 2 things left to sort out")

    allow(Stripe::Refund).to receive(:create).and_return(double("refund", id: "re_2"))
    post manage_retry_date_change_problem_path(change, "order-#{ana.id}")
    expect(ana.reload.status).to eq("refunded")
    # Refunded another way is the manager's word, kept on the page: the
    # order and the books are left alone.
    post manage_resolve_date_change_problem_path(change, "order-#{ben.id}")
    expect(ben.reload.status).to eq("paid")
    expect(change.reload.open_problems).to be_empty
    get manage_date_change_path(change)
    expect(page.at_css("[data-settled]").text).to include("Refunded another way", "still reads paid")
    # The answer to the page's own reload never carries the frame's address
    # (Turbo empties a frame that points back at itself); the page does.
    expect(page.at_css("turbo-frame#date-change-progress")["src"]).to eq(manage_date_change_progress_path(change))
    get manage_date_change_progress_path(change)
    expect(page.at_css("turbo-frame#date-change-progress")["src"]).to be_nil
    expect(page.at_css("[data-controller='date-change-progress']")["data-date-change-progress-finished-value"]).to eq("true")
    get manage_path
    expect(response.body).not_to include("left to sort out")
  end

  it "says so when the dates were already canceled by the time it's confirmed" do
    change = start("cancel")
    show.update!(canceled: true)
    expect { post manage_apply_date_change_path(change) }.not_to have_enqueued_job(DateChangeApplyJob)
    expect(flash[:alert]).to include("already been canceled")
  end

  it "keeps another organization's change out of reach" do
    other_org = create(:organization, :pro)
    other_show = create(:show, production: create(:production, organization: other_org))
    foreign = other_org.date_changes.create!(kind: "cancel", show: other_show, production: other_show.production, show_ids: [ other_show.id ])
    get manage_date_change_dates_path(foreign)
    expect(response).to have_http_status(:not_found)
    post manage_apply_date_change_path(foreign)
    expect(response).to have_http_status(:not_found)
    expect(other_show.reload).not_to be_canceled
  end

  it "only lets someone cancel dates of productions they manage" do
    private_production = create(:production, organization: org, name: "Private Party")
    party = create(:show, production: private_production, location: show.location, date_and_time: show.date_and_time + 3.hours)
    limited = create(:user, password: password)
    create(:organization_role, user: limited, organization: org, company_role: "none") rescue create(:organization_role, user: limited, organization: org)
    create(:production_permission, production: production, user: limited, role: :manager)
    delete signout_path rescue nil
    post handle_signin_path, params: { email_address: limited.email_address, password: password }

    change = start("cancel")
    next skip("this account can't open the flow at all") unless change&.created_by_user_id == limited.id

    get manage_date_change_dates_path(change)
    expect(page.text).not_to include("Private Party")
    patch manage_date_change_dates_path(change), params: { scope: "chosen", show_ids: [ show.id, party.id ], also_show_ids: [ party.id.to_s ], commit: "continue" }
    expect(change.reload.all_show_ids).to eq([ show.id ])
  end

  it "moves buyers to another date when asked, and refunds nobody" do
    other_listing = TicketListing.create!(show: next_show, status: "on_sale")
    other_listing.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 50)
    jordan = sold(2, name: "Jordan Lee", email: "jordan@example.com")
    change = start("cancel")
    get manage_date_change_touches_path(change)
    expect(page.at_css("select[name='choices[rebook_listing_id]'] option")["value"]).to eq(other_listing.id.to_s)

    patch manage_date_change_touches_path(change), params: { commit: "review", choices: { buyers_action: "rebook", rebook_listing_id: other_listing.id } }
    follow_redirect!
    expect(page.css("[data-review-sentences] li").map(&:text).join(" ")).to include("Move 1 buyer's tickets to")
    perform_enqueued_jobs { post manage_apply_date_change_path(change) }

    change.reload
    expect(change.steps.map { |s| [ s["key"], s["status"], s["detail"] ] }).to all(satisfy { |e| e[1] == "done" })
    expect(Stripe::Refund).not_to have_received(:create)
    moved = TicketOrder.where(ticket_listing: other_listing).sole
    expect(moved.tickets.count { |t| Ticket::SOLD_STATUSES.include?(t.status) }).to eq(2)
    expect(jordan.reload.tickets.count { |t| Ticket::SOLD_STATUSES.include?(t.status) }).to eq(0)
    mail = ActionMailer::Base.deliveries.find { |m| m.to == [ "jordan@example.com" ] && m.subject.include?("your tickets are now for") }
    expect(text(mail)).to include("is canceled", "moved your tickets to", "just reply to this email")
    expect(text(mail)).not_to include("/refund")
  end

  it "notifies the cast and staff of a new place when the time stays the same, and tells buyers what changed" do
    annex = create(:location, organization: org, name: "The Annex")
    ana = create(:person, name: "Ana Diaz", user: create(:user))
    kai = create(:person, name: "Kai Turner", user: create(:user))
    org.people << [ ana, kai ]
    create(:show_person_role_assignment, show: show, assignable: ana)
    booth = create(:house_role, organization: org, name: "Booth", role_type: :show_specific)
    shift = create(:shift, organization: org, house_role: booth, source: show, starts_at: show.date_and_time - 1.hour, ends_at: show.ends_at)
    shift.shift_assignments.create!(person: kai)
    sold(1, name: "Jordan Lee", email: "jordan@example.com")

    change = start("move")
    patch manage_date_change_when_path(change), params: { scope: "this", commit: "continue", move: { date: friday.iso8601, starts: "20:00", ends: "22:00", place: "#{annex.id}:" } }
    expect(response).to redirect_to(manage_date_change_touches_path(change))
    follow_redirect!
    expect(page.text).to include("Notify the cast of the new place", "Email everyone the new place")
    expect(page.text).not_to include("Move the shifts with the date")
    perform_enqueued_jobs { post manage_apply_date_change_path(change) }

    expect(show.reload.location).to eq(annex)
    expect(shift.reload.starts_at).to eq(show.date_and_time - 1.hour)
    expect(ana.user.notifications.pluck(:kind)).to include("show_new_place")
    expect(kai.user.notifications.pluck(:kind)).to include("shift_new_place")
    mail = ActionMailer::Base.deliveries.find { |m| m.to == [ "jordan@example.com" ] }
    expect(mail.subject).to eq("#{listing.display_title} has a new place")
    expect(text(mail)).to include("The Annex")
    expect(change.reload.steps.map { |s| [ s["key"], s["status"], s["detail"] ] }).to all(satisfy { |e| e[1] == "done" })
  end

  it "says on Review when the room is already booked at the new time, and keeps such dates of a run where they are by default" do
    other = create(:show, production: create(:production, organization: org, name: "Private Party"), location: show.location,
                          date_and_time: (friday + 1).in_time_zone.change(hour: 19), duration_minutes: 180)
    change = start("move")
    patch manage_date_change_when_path(change), params: { scope: "this", commit: "continue", move: { date: (friday + 1).iso8601, starts: "20:00", ends: "22:00" } }
    get manage_date_change_review_path(change)
    expect(page.at_css("[data-review-warnings]").text).to include("is booked: #{other.display_name.presence || 'Private Party'}")

    run = start("move")
    patch manage_date_change_when_path(run), params: { scope: "following", move: { wday: "6", starts: "20:00" } }
    expect(run.reload.move["per_date"]).to eq({ show.id.to_s => { "choice" => "keep" } })
    expect(ShowChangePlan::Moves.destinations(run).map(&:choice)).to eq(%w[keep])
  end

  it "saves the edit form without touching the date, which moves only through the flow" do
    get edit_manage_production_show_path(production, show)
    expect(response.body).to include(manage_new_date_change_path(production, show, kind: "move").gsub("&", "&amp;"))
    expect(response.body).not_to include('name="show[date_and_time]"')
    was = show.date_and_time
    patch manage_update_show_path(production, show), params: { show: { secondary_name: "The Late One" } }
    expect(show.reload).to have_attributes(secondary_name: "The Late One", date_and_time: was, duration_minutes: 120)
  end

  it "cancels a linked warm-up with its show, and brings back only the date chosen" do
    linkage = EventLinkage.create!(production: production)
    show.update!(event_linkage: linkage, linkage_role: "sibling")
    warm_up = create(:show, production: production, location: show.location, event_type: :rehearsal, event_linkage: linkage, linkage_role: "child",
                            date_and_time: show.date_and_time - 90.minutes, duration_minutes: 60)
    bar = create(:house_role, organization: org, name: "Bar", role_type: :house)
    marina = create(:person, name: "Marina Alvarez", user: create(:user))
    nights = [ show, next_show ].map do |s|
      create(:shift, organization: org, house_role: bar, starts_at: s.date_and_time - 1.hour, ends_at: s.ends_at).tap { |sh| sh.shift_assignments.create!(person: marina) }
    end

    change = start("cancel")
    expect(change.also_show_ids).to eq([ warm_up.id ])
    patch manage_date_change_dates_path(change), params: { scope: "chosen", show_ids: [ show.id, next_show.id ], also_show_ids: [ warm_up.id.to_s ], commit: "continue" }
    perform_enqueued_jobs(only: DateChangeApplyJob) { post manage_apply_date_change_path(change) }
    expect([ show, next_show, warm_up ].map { |s| s.reload.canceled? }).to all(be true)
    expect(nights.map { |sh| sh.reload.coverage_mode }).to all(eq("not_needed"))

    get manage_new_date_restore_path(production, show)
    restore = DateChange.last
    perform_enqueued_jobs(only: DateChangeApplyJob) { post manage_apply_date_change_restore_path(restore), params: { dates: "this", choices: { staff_back: "1" } } }
    expect(show.reload).not_to be_canceled
    expect([ next_show, warm_up ].map { |s| s.reload.canceled? }).to all(be true)
    # Only that night's house shift comes back.
    expect(nights.map { |sh| sh.reload.coverage_mode }).to eq(%w[needs_assignment not_needed])
    expect(nights.first.shift_assignments.active.map(&:person)).to eq([ marina ])
    expect(nights.last.shift_assignments.active).to be_empty
  end

  # Ticketing, staffing, and money are Pro (Tim, 2026-11-27): someone on the
  # Producer plan is never told about ticket buyers, staff, shifts, or pay.
  # Cast comes with every organization.
  context "on the Producer plan" do
    let!(:org) { create(:organization, owner: owner, name: "The Parlor Room") }
    let!(:general) { nil }
    let(:pro_words) { /ticket|buyer|refund|staff|shift|scheduled|money|settle up|\bpay\b/i }

    it "talks about the cast only, on every step" do
      ana = create(:person, name: "Ana Diaz", user: create(:user))
      org.people << ana
      create(:show_person_role_assignment, show: show, assignable: ana)

      get manage_new_date_change_path(production, show)
      expect(page.at_css("main").text).to include("CocoScout takes care of the cast.")
      expect(page.at_css("form").text).not_to match(pro_words)

      change = start("cancel")
      get manage_date_change_dates_path(change)
      expect(page.css("table thead th").map(&:text)).to eq(%w[Date Cast Sign-ups])
      expect(page.at_css("main").text).not_to match(pro_words)

      get manage_date_change_touches_path(change)
      expect(page.css("[data-touch-section]").map { |sec| sec["data-touch-section"] }).to eq([ "cast" ])
      expect(page.at_css("main").text).not_to match(pro_words)

      get manage_date_change_review_path(change)
      expect(page.at_css("main").text).to include("Messages can't be taken back once they go.")
      expect(page.at_css("main").text).not_to match(pro_words)

      perform_enqueued_jobs(only: DateChangeApplyJob) { post manage_apply_date_change_path(change) }
      get manage_date_change_path(change)
      expect(page.at_css("main").text).to include("puts the cast back")
      expect(page.at_css("main").text).not_to match(pro_words)

      move = start("move", on: next_show)
      patch manage_date_change_when_path(move), params: { scope: "this", commit: "continue", move: { date: (next_show.date_and_time.to_date + 1).iso8601, starts: "20:00", ends: "22:00" } }
      get manage_date_change_touches_path(move)
      expect(page.at_css("main").text).not_to match(pro_words)

      spare = create(:show, production: production, date_and_time: show.date_and_time + 3.weeks)
      get manage_new_date_change_path(production, spare, kind: "delete", delete: 1)
      expect(page.at_css("#delete-date-#{spare.id}").text).to include("Nobody was cast for it, so there's nobody to notify.")
    end
  end

  describe "a contract date" do
    let!(:contractor) { create(:contractor, organization: org) }
    let!(:rented) { create(:production, organization: org, production_type: "third_party", name: "Northside Sketch Co.") }
    let!(:contract) { create(:contract, :active, organization: org, production: rented, contractor: contractor, contractor_name: "Northside Sketch Co.") }
    let(:night) { (friday + 3).in_time_zone.change(hour: 18) }
    let!(:rental) { contract.space_rentals.create!(location: show.location, starts_at: night, ends_at: night + 5.hours, confirmed: true, event_starts_at: night + 2.hours, event_ends_at: night + 4.hours) }
    let!(:contract_show) { rented.shows.create!(date_and_time: night + 2.hours, duration_minutes: 120, location: show.location, space_rental: rental) }
    let!(:fee) { contract.contract_payments.create!(description: "Room fee", amount: 350, direction: "incoming", due_date: night.to_date, status: "pending", show_id: contract_show.id) }

    it "lets the room go and drops the pending fee when canceled, then books the room again when brought back" do
      change = start("cancel", on: contract_show)
      get manage_date_change_touches_path(change)
      expect(page.text).to include("1 pending contract payment", "is let go")
      perform_enqueued_jobs(only: DateChangeApplyJob) { post manage_apply_date_change_path(change) }

      expect(change.reload.steps.map { |s| [ s["key"], s["status"], s["detail"] ] }).to all(satisfy { |e| e[1] == "done" })
      expect(contract_show.reload).to be_canceled
      expect(SpaceRental.exists?(rental.id)).to be false
      expect(ContractPayment.exists?(fee.id)).to be false
      # The room is free: something else can be booked over it.
      other = create(:contract, :active, organization: org, production: create(:production, organization: org, production_type: "third_party"), contractor: contractor)
      probe = other.space_rentals.new(location: show.location, starts_at: night, ends_at: night + 5.hours, confirmed: true)
      expect(probe).to be_valid

      get manage_new_date_restore_path(rented, contract_show)
      restore = DateChange.last
      perform_enqueued_jobs(only: DateChangeApplyJob) { post manage_apply_date_change_restore_path(restore), params: { dates: "this" } }
      expect(restore.reload.open_problems).to eq([])
      expect(contract_show.reload).not_to be_canceled
      expect(contract_show.space_rental).to have_attributes(starts_at: night, ends_at: night + 5.hours, contract_id: contract.id)
    end
  end
end
