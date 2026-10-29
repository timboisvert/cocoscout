# frozen_string_literal: true

require "rails_helper"

# PDF tickets on the confirmation emails (advanced ticketing §7a): off until
# the organization turns on "Attach PDF tickets" in Ticketing → Settings →
# Box office; then one PDF, a page per ticket, drawn in the job.
RSpec.describe "PDF tickets on the confirmation emails", type: :job do
  let(:org) { create(:organization, :pro, name: "Stars & Garters") }
  let!(:profile) { TicketingProfile.for(org).tap { |p| p.update!(enabled: true, slug: "starsandgarters") } }
  let(:production) { create(:production, organization: org, name: "Improvised Animorphs") }

  def listing_on(days)
    TicketListing.create!(show: create(:show, production: production, date_and_time: days.days.from_now.change(hour: 19)), status: "on_sale")
  end

  def pdf_pages(attachment)
    attachment.body.decoded.scan(%r{/Type /Page\b}).size
  end

  before { ActionMailer::Base.deliveries.clear }

  describe TicketOrderConfirmationJob do
    let(:listing) { listing_on(5) }
    let(:general) { listing.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 20) }
    let(:order) do
      TicketCheckout.start!(listing: listing, quantities: { general.id.to_s => "2" }).tap do |order|
        TicketOrderSettlement.settle!(order)
        order.update!(buyer_name: "Avery Buyer", buyer_email: "avery@example.com")
      end
    end

    it "attaches nothing, and says nothing about a PDF, until the organization turns it on" do
      described_class.perform_now(order.id)
      mail = ActionMailer::Base.deliveries.sole
      expect(mail.attachments.map(&:filename).grep(/\.pdf\z/)).to be_empty
      expect(mail.html_part.body.to_s).not_to include("attached as a PDF")
    end

    it "attaches one PDF with a page per ticket when it's on, and says so" do
      profile.update!(attach_pdf_tickets: true)
      described_class.perform_now(order.id)
      mail = ActionMailer::Base.deliveries.sole

      pdf = mail.attachments.find { |attachment| attachment.filename == "tickets-#{order.code}.pdf" }
      expect(pdf.mime_type).to eq("application/pdf")
      expect(pdf.body.decoded).to start_with("%PDF")
      expect(pdf_pages(pdf)).to eq(2)
      expect(mail.attachments.map(&:filename).grep(/\Aticket-\d+\.png\z/).size).to eq(2)
      expect(mail.html_part.body.to_s).to include("attached as a PDF too, one page per ticket")
    end
  end

  describe TicketPurchaseConfirmationJob do
    let(:one) { listing_on(9) }
    let(:two) { listing_on(10) }
    let(:pass) do
      org.ticket_passes.create!(name: "Animorphs Double Feature", price_cents: 3_000, status: "on_sale",
                                pass_shows_attributes: [ { ticket_tier_id: one.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 20).id },
                                                         { ticket_tier_id: two.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 20).id } ])
    end
    let(:purchase) do
      order = TicketCheckout.start_pass!(pass: pass, quantity: 1)
      TicketPurchaseSettlement.settle!(order.ticket_purchase, payment_intent_id: "pi_pdf")
      order.ticket_purchase.reload.tap { |purchase| purchase.ticket_orders.each { |o| o.update!(buyer_name: "Bella Swan", buyer_email: "bella@example.com") } }
    end

    it "attaches one PDF with every show's tickets when it's on" do
      profile.update!(attach_pdf_tickets: true)
      described_class.perform_now(purchase.id)
      mail = ActionMailer::Base.deliveries.sole

      pdf = mail.attachments.find { |attachment| attachment.filename == "tickets.pdf" }
      expect(pdf_pages(pdf)).to eq(2)
      expect(mail.html_part.body.to_s).to include("attached as a PDF too")
    end

    it "attaches no PDF when it's off" do
      described_class.perform_now(purchase.id)
      mail = ActionMailer::Base.deliveries.sole
      expect(mail.attachments.map(&:filename)).not_to include("tickets.pdf")
      expect(mail.html_part.body.to_s).not_to include("attached as a PDF")
    end
  end
end
