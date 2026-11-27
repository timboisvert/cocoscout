# frozen_string_literal: true

require "rails_helper"

# Cancel or move this date (Tim, 2026-11-27): one flow for canceling,
# moving, deleting and bringing back dates. Choose what's happening and which
# dates, see everything it touches, review it, confirm; CocoScout does all of
# it and the change's page keeps the record.
RSpec.describe "Cancel or move this date", type: :request do
  include ActiveJob::TestHelper

  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner, name: "The Parlor Room") }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org, name: "The Friday Show") }
  let(:group_id) { SecureRandom.uuid }
  let(:first_friday) { (Date.current + 14).next_occurring(:friday) }
  let!(:fridays) do
    (0..3).map do |i|
      create(:show, production: production, recurrence_group_id: group_id, recurrence_pattern: "weekly",
                    date_and_time: (first_friday + (7 * i)).in_time_zone.change(hour: 20), duration_minutes: 120)
    end
  end
  let(:dec4) { fridays.first }

  let(:ana) { create(:person, name: "Ana Diaz", user: create(:user)) }
  let(:kai) { create(:person, name: "Kai Turner", user: create(:user)) }
  let(:booth) { create(:house_role, organization: org, name: "Booth", role_type: :show_specific) }
  let!(:booth_shifts) do
    fridays.first(2).map do |show|
      create(:shift, organization: org, house_role: booth, source: show, starts_at: show.date_and_time - 1.hour, ends_at: show.ends_at)
    end
  end

  let(:listing) { create(:ticket_listing, organization: org, show: dec4) }
  let!(:general) { listing.ticket_tiers.create!(name: "General", price_cents: 2_000) }

  before do
    org.people << [ ana, kai ]
    fridays.first(2).each { |show| create(:show_person_role_assignment, show: show, assignable: ana) }
    booth_shifts.each { |shift| shift.shift_assignments.create!(person: kai) }
    allow(Stripe::Refund).to receive(:create).and_return(double("refund", id: "re_1"))
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
  end

  def sold(count, name:, email:)
    order = TicketCheckout.start!(listing: listing, quantities: { general.id.to_s => count.to_s })
    order.update!(buyer_name: name, buyer_email: email)
    TicketOrderSettlement.settle!(order, payment_intent_id: "pi_#{name.parameterize}")
    order.reload
  end

  def page = Nokogiri::HTML(response.body)

  describe "canceling" do
    it "walks from What to do to the record, and does every part of it" do
      jordan = sold(2, name: "Jordan Lee", email: "jordan@example.com")

      get manage_new_date_change_path(production, dec4)
      expect(response).to have_http_status(:ok)
      expect(page.text).to include("What would you like to do with", "Cancel it", "Move it", "Delete it")
      # Tickets were sold, so Delete isn't offered.
      expect(page.at_css("input[name='kind'][value='delete']")["disabled"]).to be_present

      post manage_create_date_change_path(production, dec4), params: { kind: "cancel" }
      change = DateChange.last
      expect(response).to redirect_to(manage_date_change_dates_path(change))
      follow_redirect!
      expect(response).to have_http_status(:ok)
      expect(page.text).to include("Which dates are you canceling?", "and the 3 dates after it")

      patch manage_date_change_dates_path(change), params: { scope: "following" }
      expect(response).to redirect_to(manage_date_change_dates_path(change))
      expect(change.reload.show_ids).to eq(fridays.map(&:id))

      patch manage_date_change_dates_path(change), params: { scope: "following", commit: "continue" }
      expect(response).to redirect_to(manage_date_change_touches_path(change))
      follow_redirect!
      expect(response).to have_http_status(:ok)
      sections = page.css("[data-touch-section]").map { |s| s["data-touch-section"] }
      expect(sections).to include("buyers", "cast", "staff")
      expect(page.at_css("[data-touch-section='staff']").text).to include("Kai Turner", "Comes off")

      patch manage_date_change_touches_path(change), params: { commit: "review", choices: { buyers_action: "refund", cast_notify: "1", shifts_off: "1", staff_notify: "1" } }
      expect(response).to redirect_to(manage_date_change_review_path(change))
      follow_redirect!
      expect(response).to have_http_status(:ok)
      sentences = page.css("[data-review-sentences] li").map(&:text)
      expect(sentences.first).to include("Cancel The Friday Show on")
      expect(sentences.join(" ")).to include("Refund 1 buyer $", "Take 2 shifts off the schedule", "notify Kai Turner")

      perform_enqueued_jobs(only: DateChangeApplyJob) do
        post manage_apply_date_change_path(change)
      end
      expect(response).to redirect_to(manage_date_change_path(change))

      expect(fridays.map { |s| s.reload.canceled? }).to all(be true)
      expect(listing.reload.status).to eq("canceled")
      expect(jordan.reload.status).to eq("refunded")
      expect(booth_shifts.map { |s| s.reload.coverage_mode }).to all(eq("not_needed"))
      expect(ShiftAssignment.where(shift: booth_shifts)).to be_empty
      change.reload
      expect(change.status).to eq("applied")
      expect(change.steps.map { |s| [ s["key"], s["status"] ] }).to all(satisfy { |_, status| status == "done" })
      expect(ShowChangeNotice.where(person: ana, audience: "cast")).to exist
      expect(ShowChangeNotice.where(person: kai, audience: "staff")).to exist
      expect(ShowChange.where(batch: change.batch).pluck(:closed_at)).to all(be_present)

      get manage_date_change_path(change)
      expect(response).to have_http_status(:ok)
      expect(page.text).to include("Canceled by", "Progress")
      expect(page.css("[data-progress-steps] li[data-status='done']").size).to eq(change.steps.size)
    end
  end

  describe "moving" do
    it "moves the date in place, its shift with it, emails buyers with a refund link, and notifies the cast" do
      jordan = sold(1, name: "Jordan Lee", email: "jordan@example.com")
      saturday = dec4.date_and_time.to_date + 1

      post manage_create_date_change_path(production, dec4), params: { kind: "move" }
      change = DateChange.last
      expect(response).to redirect_to(manage_date_change_when_path(change))
      follow_redirect!
      expect(response).to have_http_status(:ok)
      expect(page.text).to include("Where does it go?")

      patch manage_date_change_when_path(change), params: { scope: "this", move: { date: saturday.iso8601, starts: "20:00", ends: "22:00" } }
      follow_redirect!
      expect(page.text).to include("#{saturday.strftime('%A, %B %-d')}, checked", "is free from 8:00 to 10:00 PM")

      patch manage_date_change_when_path(change), params: { scope: "this", commit: "continue", move: { date: saturday.iso8601, starts: "20:00", ends: "22:00" } }
      expect(response).to redirect_to(manage_date_change_touches_path(change))
      follow_redirect!
      expect(response).to have_http_status(:ok)
      expect(page.at_css("[data-touch-section='staff']").text).to include("Kai Turner", "Moves, notified")

      patch manage_date_change_touches_path(change), params: { commit: "review", choices: { buyers_email: "1", buyers_refund_offer: "1", shifts_move: "1", staff_notify: "1", cast_notify: "1" } }
      follow_redirect!
      expect(page.css("[data-review-sentences] li").map(&:text).join(" ")).to include("from #{dec4.date_and_time.strftime('%a, %b %-d')}, 8:00 PM to #{saturday.strftime('%a, %b %-d')}, 8:00 PM")

      was_shift = booth_shifts.first.starts_at
      perform_enqueued_jobs(only: [ DateChangeApplyJob, ActionMailer::MailDeliveryJob ]) { post manage_apply_date_change_path(change) }

      expect(dec4.reload.date_and_time).to eq(saturday.in_time_zone.change(hour: 20))
      expect(booth_shifts.first.reload.starts_at).to eq(was_shift + 1.day)
      expect(booth_shifts.first.shift_assignments.active.map(&:person)).to eq([ kai ])
      expect(change.reload.steps.map { |st| [ st["key"], st["status"], st["detail"] ] }).to all(satisfy { |e| e[1] == "done" })
      expect(ShowChangeNotice.where(person: kai, audience: "staff")).to exist

      mail = ActionMailer::Base.deliveries.find { |m| m.to == [ "jordan@example.com" ] }
      body = mail.html_part&.body&.decoded || mail.body.decoded
      expect(body).to include("are now for #{saturday.strftime('%A, %B %-d')} at 8:00 PM")
      link = body[%r{https?://[^"<\s]+/change/#{change.id}/refund}]
      expect(link).to be_present

      # The buyer's own refund, from the link, before the show.
      get tickets_date_change_refund_path(token: jordan.token, change_id: change.id)
      expect(page.text).to include("Refund my tickets")
      post tickets_date_change_refund_issue_path(token: jordan.token, change_id: change.id)
      expect(jordan.reload.status).to eq("refunded")
      expect(change.reload.summary["buyer_refunds"].sole["order_id"]).to eq(jordan.id)
    end

    it "moves a run of dates to another weekday, keeping a date whose room is booked where it is" do
      other = create(:production, organization: org, name: "Private")
      saturday_last = fridays.last.date_and_time.to_date + 1
      create(:show, production: other, location: fridays.last.location, date_and_time: saturday_last.in_time_zone.change(hour: 19), duration_minutes: 240)

      post manage_create_date_change_path(production, dec4), params: { kind: "move" }
      change = DateChange.last
      patch manage_date_change_when_path(change), params: { scope: "following", move: { wday: "6", starts: "20:30" } }
      follow_redirect!
      expect(response).to have_http_status(:ok)
      expect(page.text).to include("Each date, checked", "is booked")

      patch manage_date_change_when_path(change), params: { scope: "following", commit: "continue",
                                                            move: { wday: "6", starts: "20:30", per_date: { fridays.last.id.to_s => { choice: "keep" } } } }
      expect(response).to redirect_to(manage_date_change_touches_path(change))
      perform_enqueued_jobs(only: DateChangeApplyJob) { post manage_apply_date_change_path(change) }

      expect(fridays.first(3).map { |s| s.reload.date_and_time.strftime("%a %H:%M") }).to all(eq("Sat 20:30"))
      expect(fridays.last.reload.date_and_time.strftime("%a %H:%M")).to eq("Fri 20:00")
      expect(fridays.map(&:id)).to all(satisfy { |id| Show.exists?(id) })
    end
  end

  describe "deleting" do
    it "deletes a date nobody counts on, and refuses one that sold tickets" do
      spare = fridays.last
      get manage_new_date_change_path(production, spare, kind: "delete", delete: 1)
      expect(page.at_css("#delete-date-#{spare.id}")["class"]).not_to include("hidden")
      expect(page.text).to include("Delete #{spare.date_and_time.strftime('%A, %B %-d')}?")

      delete manage_delete_dates_path(production, spare), params: { scope: "this" }
      expect(Show.exists?(spare.id)).to be false

      sold(1, name: "Jordan Lee", email: "jordan@example.com")
      delete manage_delete_dates_path(production, dec4), params: { scope: "this" }
      expect(Show.exists?(dec4.id)).to be true
      expect(flash[:alert]).to include("can't be deleted", "1 ticket sold to 1 buyer")
    end
  end

  describe "bringing dates back" do
    it "brings canceled dates back with sales reopened and the staff back on their shifts" do
      post manage_create_date_change_path(production, dec4), params: { kind: "cancel" }
      cancel = DateChange.last
      patch manage_date_change_dates_path(cancel), params: { scope: "following", commit: "continue" }
      perform_enqueued_jobs(only: DateChangeApplyJob) { post manage_apply_date_change_path(cancel) }
      expect(dec4.reload).to be_canceled

      get manage_new_date_change_path(production, dec4)
      expect(response).to redirect_to(manage_new_date_restore_path(production, dec4))
      follow_redirect!
      restore = DateChange.last
      expect(restore.restores).to eq(cancel)
      follow_redirect!
      expect(response).to have_http_status(:ok)
      expect(page.text).to include("Everything canceled with it: 4 dates")

      perform_enqueued_jobs(only: DateChangeApplyJob) do
        post manage_apply_date_change_restore_path(restore), params: { dates: "all", choices: { cast_notify: "1", staff_back: "1" } }
      end
      expect(fridays.map { |s| s.reload.canceled? }).to all(be false)
      expect(listing.reload.status).to eq("on_sale")
      expect(booth_shifts.map { |sh| sh.reload.shift_assignments.active.map(&:person) }).to all(eq([ kai ]))
      expect(booth_shifts.map { |sh| sh.coverage_mode }).to all(eq("needs_assignment"))
      expect(restore.reload.steps.map { |st| st["status"] }).to all(eq("done"))
    end
  end
end
