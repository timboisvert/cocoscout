# frozen_string_literal: true

require "rails_helper"

# A discount code that only works on an order of X or more tickets (Tim,
# 2026-11-24). On the code's form the two limits are toggles (limit the
# number of uses, require a minimum number of tickets), a code can be edited
# with the same form it was added with, and the buyer sees the discount on
# the ticket page itself: under the minimum the page says how many tickets
# the code takes and the order goes through at full price.
RSpec.describe "A discount code's minimum number of tickets", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, email_address: "owner@sg.example", password: password) }
  let(:org) { create(:organization, :pro, name: "Stars & Garters", owner: owner) }
  let!(:profile) { TicketingProfile.for(org).tap { |p| p.update!(enabled: true, slug: "starsandgarters") } }
  let(:production) { create(:production, organization: org, name: "Stargazers") }
  let(:show) { create(:show, production: production, date_and_time: 6.days.from_now.change(hour: 19, min: 30)) }
  let!(:listing) { TicketListing.create!(show: show, status: "on_sale") }
  let!(:general) { listing.ticket_tiers.create!(name: "General", price_cents: 2_500, quantity: 60) }

  def group_code(**attributes)
    org.ticket_discount_codes.create!(production: production, code: "GROUP10", kind: "percent", percent: 10, min_tickets: 6, **attributes)
  end

  describe "the code itself" do
    it "says its minimum in words, and a minimum of 1 or none is no minimum" do
      code = group_code
      expect([ code.minimum?, code.minimum_words, code.terms_words ]).to eq([ true, "6 or more tickets", "10% off 6 or more tickets" ])
      expect(code.buyer_sentence).to eq("Your code GROUP10 takes 10% off an order of 6 or more tickets.")

      code.update!(min_tickets: 1)
      expect([ code.minimum?, code.minimum_words, code.buyer_sentence ]).to eq([ false, nil, "Your code GROUP10 takes 10% off." ])

      five = org.ticket_discount_codes.create!(production: production, code: "FIVE", kind: "fixed", amount_cents: 500, min_tickets: 4)
      expect(five.buyer_sentence).to eq("Your code FIVE takes $5.00 off each ticket on an order of 4 or more tickets.")
    end

    it "takes a whole number of tickets, 1 or more" do
      [ 0, -2, "six", "2.5" ].each do |bad|
        code = org.ticket_discount_codes.new(code: "BAD", kind: "percent", percent: 10, min_tickets: bad)
        expect(code).not_to be_valid
        expect(code.errors.full_messages).to eq([ "Enter the minimum number of tickets, 1 or more" ])
      end
    end

    it "counts the people on the ticket types it takes money off: a table for four is four" do
      table = listing.ticket_tiers.create!(name: "Table for four", price_cents: 10_000, admits: 4, bundle_of: general)
      vip = listing.ticket_tiers.create!(name: "VIP", price_cents: 4_000, quantity: 10)
      code = group_code(ticket_tier_ids: [ general.id, table.id ])

      expect(code.tickets_counted(listing, { general => 2, table => 1, vip => 3 })).to eq(6)
      expect(code.minimum_met?(listing, { general => 2, table => 1, vip => 3 })).to be(true)
      expect(code.minimum_met?(listing, { general => 5, vip => 3 })).to be(false)
    end
  end

  describe "reading the form" do
    def attributes(raw)
      TicketDiscountCode.attributes_from_form(ActionController::Parameters.new(raw).permit(*TicketDiscountCode::FORM_FIELDS))
    end

    it "keeps a number only while its toggle is on" do
      on = attributes(code: "group10", kind: "percent", amount: "10", limit_uses: "1", max_uses: "50", require_minimum: "1", min_tickets: "6")
      expect(on.slice(:max_uses, :min_tickets)).to eq(max_uses: "50", min_tickets: "6")

      off = attributes(code: "group10", kind: "percent", amount: "10", limit_uses: "0", max_uses: "50", require_minimum: "0", min_tickets: "6")
      expect(off.slice(:max_uses, :min_tickets)).to eq(max_uses: nil, min_tickets: nil)
    end

    it "refuses a toggle that's on with no number typed" do
      code = org.ticket_discount_codes.new(attributes(code: "group10", kind: "percent", amount: "10", require_minimum: "1", min_tickets: ""))
      expect(code).not_to be_valid
      expect(code.errors.full_messages).to eq([ "Enter the minimum number of tickets, 1 or more" ])
    end

    it "reads a spreadsheet row, which has no toggles, by its numbers" do
      expect(TicketDiscountCode.attributes_from_form(code: "A", kind: "fixed", amount: "5", max_uses: "20", min_tickets: "4"))
        .to include(max_uses: "20", min_tickets: "4")
    end
  end

  describe "at checkout" do
    def start(count, code: "group10")
      TicketCheckout.start!(listing: listing, quantities: { general.id.to_s => count }, code: code)
    end

    it "takes the discount off an order that reaches the minimum" do
      code = group_code
      order = start(6)

      expect([ order.subtotal_cents, order.discount_cents, order.ticket_discount_code ]).to eq([ 15_000, 1_500, code ])
    end

    it "lets an order under the minimum through at full price, and doesn't count it as a use" do
      code = group_code(max_uses: 1)
      order = start(5)

      expect([ order.subtotal_cents, order.discount_cents, order.ticket_discount_code ]).to eq([ 12_500, 0, nil ])
      order.update!(status: "paid")
      expect(code.reload.usable?).to be(true)
    end

    it "still refuses a code that isn't this show's" do
      group_code
      expect { start(6, code: "NOPE") }.to raise_error(TicketCheckout::Error, "That code doesn't work for this show.")
    end
  end

  describe "the buyer's ticket page" do
    def event_path(**params)
      tickets_event_path(org: "starsandgarters", event: listing.slug, **params)
    end

    it "shows the code's terms, each price with the code, and the numbers the total is made from" do
      group_code
      get event_path(code: "group10")
      doc = Nokogiri::HTML(response.body)

      expect(doc.at_css("[data-ticket-picker-target='codeNote']").text).to eq("Your code GROUP10 takes 10% off an order of 6 or more tickets.")
      expect(response.body).not_to include("is applied at checkout")
      form = doc.at_css("form[data-controller='ticket-picker']")
      expect(form["data-ticket-picker-code-min-value"]).to eq("6")
      expect(form["data-ticket-picker-code-label-value"]).to eq("GROUP10, 10% off")
      row = doc.at_css("[data-ticket-picker-target='row']")
      expect([ row["data-counts"], row["data-off"], row["data-off-paid"] ]).to eq(%w[1 250 1])
      # The price with the code waits beside the price without it, hidden
      # until the order reaches the minimum.
      expect(row.at_css("[data-off-price]")["hidden"]).not_to be_nil
      expect(row.at_css("[data-off-price] .line-through").text.strip).to eq(row.at_css("[data-full-price]").text[/\$\d+\.\d\d/])
      # The code's own line, and Remove in place of the code box.
      expect(doc.at_css("[data-ticket-picker-target='codeLine']").text.squish).to start_with("GROUP10, 10% off")
      applied = doc.at_css("[data-applied-code]")
      expect(applied.text.squish).to include("GROUP10 · 10% off 6 or more tickets", "Remove")
      # Remove goes back to the same date without the code.
      expect(applied.at_css("a[data-keep-cart='click']")["href"]).to include(listing.slug).and(satisfy { |href| !href.include?("code=") })
      expect(doc.at_css("input[name='code'][type='text']")).to be_nil
    end

    it "prices a ticket with the code the way checkout charges it" do
      code = group_code(min_tickets: nil)
      get event_path(code: "group10")
      shown = Nokogiri::HTML(response.body).at_css("[data-off-price] .text-pink-700").text.strip

      order = TicketCheckout.start!(listing: listing, quantities: { general.id.to_s => 1 }, code: "group10")
      expect(order.ticket_discount_code).to eq(code)
      expect(shown).to eq(ActiveSupport::NumberHelper.number_to_currency(order.total_cents / 100.0))
    end

    # Apply used to send a buyer on a production's page back to its list of
    # dates: a GET form drops its address's query, and the date was in it.
    it "keeps the date and the tickets chosen when a code is applied" do
      get event_path
      form = Nokogiri::HTML(response.body).at_css("form[data-keep-cart='submit']")

      expect(form.at_css("input[name='code']")).to be_present
      expect(form["action"]).not_to include("?")
      expect(form.at_css("input[type='hidden'][name='date']")["value"]).to eq(listing.slug)

      get form["action"], params: { date: listing.slug, code: "nope" }
      expect(response.body).to include("That code doesn&#39;t work for this show.", "data-controller=\"ticket-picker\"")
    end

    it "leaves a ticket type the code doesn't cover at its price" do
      vip = listing.ticket_tiers.create!(name: "VIP", price_cents: 4_000, quantity: 10)
      group_code(ticket_tier_ids: [ general.id ])
      get event_path(code: "group10")
      rows = Nokogiri::HTML(response.body).css("[data-ticket-picker-target='row']").index_by { |row| row["data-tier-id"].to_i }

      expect(rows[vip.id]["data-counts"]).to be_nil
      expect(rows[vip.id].at_css("[data-off-price]")).to be_nil
      expect(rows[general.id]["data-off"]).to eq("250")
    end
  end

  describe "the Discount codes tab" do
    before do
      create(:organization_role, :manager, user: owner, organization: org)
      post handle_signin_path, params: { email_address: owner.email_address, password: password }
      post set_organization_path(id: org.id)
    end

    it "adds a code with both limits behind their toggles" do
      post manage_production_ticketing_codes_path(production),
           params: { ticket_discount_code: { code: "group10", kind: "percent", amount: "10", limit_uses: "1", max_uses: "50",
                                             require_minimum: "1", min_tickets: "6", shared_with: "nobody" } }
      code = org.ticket_discount_codes.sole
      expect([ code.code, code.percent.to_i, code.max_uses, code.min_tickets, code.shared_with ]).to eq([ "GROUP10", 10, 50, 6, "nobody" ])

      get manage_edit_production_ticketing_path(production, section: "codes")
      doc = Nokogiri::HTML(response.body)
      expect(doc.at_css("[data-code-minimum]").text).to include("6 or more tickets")
      # Add's form: both toggles off, with the number each one shows.
      add = doc.at_css("#add-code-modal")
      expect(add.at_css("#code-limit-uses-new")["checked"]).to be_nil
      expect(add.at_css("#code-require-minimum-new")["checked"]).to be_nil
      expect(add.at_css("[data-show-when='code-require-minimum-new'] input[name='ticket_discount_code[min_tickets]']")).to be_present
      expect(add.text.squish).to include("Limit the number of uses", "Require a minimum number of tickets", "The code only works on an order of", "or more tickets.")
    end

    it "reports a minimum toggle that's on with no number, and adds nothing" do
      post manage_production_ticketing_codes_path(production),
           params: { ticket_discount_code: { code: "group10", kind: "percent", amount: "10", require_minimum: "1", min_tickets: "" } }
      expect(flash[:alert]).to eq("Enter the minimum number of tickets, 1 or more")
      expect(org.ticket_discount_codes).to be_empty
    end

    it "edits a code with the same form, filled in" do
      code = group_code(max_uses: 50)
      get manage_edit_production_ticketing_path(production, section: "codes")
      doc = Nokogiri::HTML(response.body)
      edit = doc.at_css("#edit-code-#{code.id}")

      expect(edit.at_css("h3").text).to eq("Edit GROUP10")
      expect(edit.at_css("form")["action"]).to eq(manage_production_ticketing_code_path(production, code_id: code.id))
      expect(edit.at_css("input[name='_method']")["value"]).to eq("patch")
      expect(edit.at_css("input[name='ticket_discount_code[code]']")["value"]).to eq("GROUP10")
      expect(edit.at_css("input[name='ticket_discount_code[amount]']")["value"]).to eq("10")
      expect(edit.at_css("select[name='ticket_discount_code[kind]'] option[selected]")["value"]).to eq("percent")
      expect(edit.at_css("#code-limit-uses-#{code.id}")["checked"]).not_to be_nil
      expect(edit.at_css("input[name='ticket_discount_code[max_uses]']")["value"]).to eq("50")
      expect(edit.at_css("input[name='ticket_discount_code[min_tickets]']")["value"]).to eq("6")
      expect(edit.to_html).not_to match(/bg-red|text-red/)
      expect(doc.css("[data-modal-id='edit-code-#{code.id}']").map(&:text).map(&:squish)).to eq([ "Edit" ])

      patch manage_production_ticketing_code_path(production, code_id: code.id),
            params: { ticket_discount_code: { code: "group15", kind: "percent", amount: "15", limit_uses: "0", max_uses: "50",
                                              require_minimum: "1", min_tickets: "8", shared_with: "team" } }
      expect(flash[:notice]).to eq("Saved GROUP15.")
      expect(code.reload.attributes.slice("code", "max_uses", "min_tickets", "shared_with")).to eq("code" => "GROUP15", "max_uses" => nil, "min_tickets" => 8, "shared_with" => "team")
      expect(code.percent.to_i).to eq(15)
    end

    it "keeps a code as it was when an edit can't be read" do
      code = group_code
      patch manage_production_ticketing_code_path(production, code_id: code.id),
            params: { ticket_discount_code: { code: "group10", kind: "percent", amount: "ten", require_minimum: "1", min_tickets: "6" } }
      expect(flash[:alert]).to be_present
      expect([ code.reload.kind, code.percent.to_i ]).to eq([ "percent", 10 ])
    end

    it "still changes who a code is shared with from its row" do
      code = group_code
      patch manage_production_ticketing_code_path(production, code_id: code.id), params: { shared_with: "nobody" }
      expect([ code.reload.shared_with, code.min_tickets ]).to eq([ "nobody", 6 ])
    end

    # The date's row could not change a code at all before this: the action
    # never loaded the date (found 2026-11-24).
    it "edits a date's own code too, and changes who it is shared with from its row" do
      code = org.ticket_discount_codes.create!(ticket_listing: listing, code: "TONIGHT", kind: "fixed", amount_cents: 500)
      listing.update!(own_codes: true)
      get manage_edit_ticket_listing_path(listing, section: "codes")
      expect(Nokogiri::HTML(response.body).at_css("#edit-code-#{code.id} h3").text).to eq("Edit TONIGHT")

      patch manage_ticket_listing_code_path(listing, code_id: code.id),
            params: { ticket_discount_code: { code: "tonight", kind: "fixed", amount: "5", limit_uses: "0", require_minimum: "1", min_tickets: "4" } }
      expect(flash[:notice]).to eq("Saved TONIGHT.")
      expect(code.reload.min_tickets).to eq(4)

      patch manage_ticket_listing_code_path(listing, code_id: code.id), params: { shared_with: "team" }
      expect(code.reload.shared_with).to eq("team")
    end

    it "carries the minimum in the spreadsheet, out and back in" do
      group_code
      get manage_production_ticketing_codes_export_path(production)
      expect(response.body.lines.map(&:chomp)).to eq([ "Code,Kind,Amount,Most uses,Minimum tickets,Shared with", "GROUP10,% off,10,,6,Production team and cast" ])

      other = create(:production, organization: org, name: "Encore")
      result = DiscountCodeCsv.import(organization: org, production: other, text: response.body)
      expect(result.added.sole.min_tickets).to eq(6)
    end
  end
end
