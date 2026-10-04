# frozen_string_literal: true

require "rails_helper"

# Reminders before the show: as many days ahead as the theater chose, once
# per order, never to buyers who stopped them or just bought.
RSpec.describe TicketRemindersJob do
  include ActiveJob::TestHelper

  let(:org) { create(:organization, :pro, name: "Stars & Garters") }
  let(:today) { Date.new(2026, 10, 8) }
  let(:listing) { create(:ticket_listing, organization: org) }
  let!(:general) { listing.ticket_tiers.create!(name: "General", price_cents: 2_000) }

  before do
    TicketingProfile.for(org).update!(enabled: true, reminder_days_before: 2)
    listing.show.update!(date_and_time: Time.zone.local(2026, 10, 10, 19, 30))
    listing.update!(door_note: "Doors open at 7. Enter on Clark St.")
    listing.show.location&.update!(address1: "1 Clark St", city: "Chicago")
  end

  def order(name, paid_at: Time.zone.local(2026, 10, 1, 12), **attrs)
    o = create(:ticket_order, ticket_listing: listing, status: "paid", paid_at: paid_at, money_path: "cocoscout",
                              expires_at: nil, buyer_name: name, buyer_email: "#{name.parameterize}@example.com", **attrs)
    create(:ticket, ticket_order: o, ticket_tier: general)
    o
  end

  it "reminds each order once, the chosen number of days before" do
    reminded = order("Dana Scully")
    stopped = order("Fox Mulder", reminders_opt_out: true)
    just_bought = order("Walter Skinner", paid_at: Time.zone.local(2026, 10, 8, 9))
    refunded = order("Alex Krycek", status: "refunded")

    travel_to Time.zone.local(2026, 10, 8, 10) do
      expect { described_class.perform_now(today) }.to have_enqueued_mail(TicketOrderMailer, :reminder).exactly(:once)
      expect { described_class.perform_now(today) }.not_to have_enqueued_mail(TicketOrderMailer, :reminder)
    end
    expect(reminded.reload.reminded_at).to be_present
    expect([ stopped, just_bought, refunded ].map { |o| o.reload.reminded_at }).to all(be_nil)

    expect { described_class.perform_now(today - 1) }.not_to have_enqueued_mail(TicketOrderMailer, :reminder)
  end

  it "sends nothing when reminders are off, or ticketing is" do
    order("Dana Scully")
    TicketingProfile.for(org).update!(reminder_days_before: nil)
    travel_to(Time.zone.local(2026, 10, 8, 10)) { expect { described_class.perform_now(today) }.not_to have_enqueued_mail }

    TicketingProfile.for(org).update!(reminder_days_before: 2, enabled: false)
    travel_to(Time.zone.local(2026, 10, 8, 10)) { expect { described_class.perform_now(today) }.not_to have_enqueued_mail }
  end

  it "carries the time, the place, the door note, the tickets and a way to stop" do
    o = order("Dana Scully")
    mail = travel_to(Time.zone.local(2026, 10, 8, 10)) { TicketOrderMailer.reminder(o).message }

    expect(mail.subject).to eq("Reminder: #{listing.display_title} is on Saturday")
    html = (mail.html_part || mail).body.decoded
    expect(html).to include("See you on Saturday", "7:30 PM", "1 Clark St, Chicago", "Doors open at 7. Enter on Clark St.",
                            "/tickets/orders/#{o.token}/reminders")
    expect(mail.attachments.map(&:filename)).to include("ticket-#{o.tickets.sole.id}.png")
    expect(mail["List-Unsubscribe"].value).to include("/tickets/orders/#{o.token}/reminders/stop")
    expect(mail.from).to eq([ "info@cocoscout.com" ])
  end

  it "escapes what people typed" do
    o = order("Dana Scully")
    o.update!(buyer_name: "<b>Dana</b> Scully")
    mail = TicketOrderMailer.reminder(o)
    html = (mail.html_part || mail).body.decoded
    expect(html).to include("Hi &lt;b&gt;Dana&lt;/b&gt;")
    expect(html).not_to include("<b>Dana</b>")
  end

  describe "stopping reminders from the email", type: :request do
    it "shows a page with one button, then stops them" do
      o = order("Dana Scully")
      get tickets_order_reminders_path(token: o.token)
      expect(response.body).to include("Stop reminder emails")
      expect(o.reload.reminders_opt_out).to be(false)

      post tickets_order_stop_reminders_path(token: o.token)
      expect(response).to redirect_to(tickets_order_path(token: o.token))
      expect(o.reload.reminders_opt_out).to be(true)
    end
  end
end
