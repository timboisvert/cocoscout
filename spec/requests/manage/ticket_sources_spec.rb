# frozen_string_literal: true

require "rails_helper"

# Ticket sales are entered per source now: the org names its sources in Money
# settings, the worksheet carries a line each, and the two long-standing
# columns everything else reads become rollups of those lines.
RSpec.describe "Ticket sources and per-source sales", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org) }
  let!(:show) do
    create(:show, production: production, date_and_time: Time.zone.local(2026, 9, 18, 20), duration_minutes: 120)
  end

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  describe "Money settings" do
    it "lists the section and takes a new source" do
      get manage_money_settings_section_path(section: "ticket_sources")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Where you sell tickets")

      expect {
        post manage_money_settings_ticket_sources_path, params: { ticket_source: { name: "Eventbrite" } }
      }.to change { org.ticket_sources.count }.by(1)

      expect(org.ticket_sources.last.name).to eq("Eventbrite")
    end

    it "refuses a second source with the same name" do
      org.ticket_sources.create!(name: "Eventbrite")

      expect {
        post manage_money_settings_ticket_sources_path, params: { ticket_source: { name: "eventbrite" } }
      }.not_to change { org.ticket_sources.count }

      expect(flash[:alert]).to be_present
    end

    it "archives rather than deletes, and can put one back" do
      source = org.ticket_sources.create!(name: "HotTix")

      expect {
        delete manage_money_settings_ticket_source_path(source)
      }.not_to change { org.ticket_sources.count }
      expect(source.reload).to be_archived

      patch manage_money_settings_restore_ticket_source_path(source)
      expect(source.reload).not_to be_archived
    end

    it "won't touch another organization's source" do
      other = create(:organization, :pro)
      theirs = other.ticket_sources.create!(name: "Not yours")

      patch manage_money_settings_ticket_source_path(theirs), params: { ticket_source: { name: "Mine now" } }

      expect(response).not_to have_http_status(:ok)
      expect(theirs.reload.name).to eq("Not yours")
    end
  end

  describe "the financials worksheet" do
    let!(:eventbrite) { org.ticket_sources.create!(name: "Eventbrite", position: 1) }
    let!(:door) { org.ticket_sources.create!(name: "At the door", position: 2) }

    it "offers a line per source on the worksheet" do
      # The worksheet is a modal on the financials page, not a page of its own.
      get manage_money_show_financials_path(show)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Ticket sales")
      expect(response.body).to include("show_financials[ticket_sales_lines_attributes]")
      expect(response.body).to include("Eventbrite").and include("At the door")
    end

    it "saves the lines and rolls them into the columns everything else reads" do
      patch manage_update_money_show_financials_path(show), params: {
        show_financials: {
          revenue_type: "ticket_sales",
          data_confirmed: "1",
          ticket_sales_lines_attributes: {
            "0" => { ticket_source_id: eventbrite.id, tickets_sold: "40", amount: "400.00" },
            "1" => { ticket_source_id: door.id, tickets_sold: "12", amount: "144.00" }
          }
        }
      }

      financials = show.reload.show_financials
      expect(financials.ticket_sales_lines.count).to eq(2)
      expect(financials.ticket_count).to eq(52)
      expect(financials.ticket_revenue).to eq(544)
      expect(financials.total_revenue).to eq(544)
    end

    it "ignores a line nobody filled in" do
      patch manage_update_money_show_financials_path(show), params: {
        show_financials: {
          revenue_type: "ticket_sales",
          ticket_sales_lines_attributes: { "0" => { ticket_source_id: "", tickets_sold: "0", amount: "0" } }
        }
      }

      expect(show.reload.show_financials.ticket_sales_lines).to be_empty
    end

    # The worksheet is a grid: a row per source, no picker, no "add a line".
    it "lays out a row for every source, each already naming its source" do
      get manage_money_show_financials_path(show)

      body = response.body
      expect(body).to include("Sold through").and include("Total")
      expect(body).not_to include("Add a line")
      field = ->(i) { body[/<input[^>]*name="show_financials\[ticket_sales_lines_attributes\]\[#{i}\]\[ticket_source_id\]"[^>]*>/] }
      expect(field.call(0)).to include(%(value="#{eventbrite.id}"))
      expect(field.call(1)).to include(%(value="#{door.id}"))
    end

    it "saves a row with tickets and no money — comps are a real row" do
      patch manage_update_money_show_financials_path(show), params: {
        show_financials: { revenue_type: "ticket_sales", ticket_sales_lines_attributes: {
          "0" => { ticket_source_id: eventbrite.id, tickets_sold: "30", amount: "400" },
          "1" => { ticket_source_id: door.id, tickets_sold: "12", amount: "" }
        } }
      }
      lines = show.reload.show_financials.ticket_sales_lines
      expect(lines.map { |l| [ l.ticket_source_id, l.tickets_sold, l.amount.to_f ] })
        .to contain_exactly([ eventbrite.id, 30, 400.0 ], [ door.id, 12, 0.0 ])
      expect(show.show_financials.ticket_count).to eq(42)
    end

    it "keeps both sources when the second is filled in on a later save, and drops one cleared to nothing" do
      patch manage_update_money_show_financials_path(show), params: {
        show_financials: { revenue_type: "ticket_sales", ticket_sales_lines_attributes: {
          "0" => { ticket_source_id: eventbrite.id, tickets_sold: "30", amount: "400" },
          "1" => { ticket_source_id: door.id, tickets_sold: "", amount: "" }
        } }
      }
      financials = show.reload.show_financials
      tt = financials.ticket_sales_lines.sole
      expect(tt.ticket_source).to eq(eventbrite)

      patch manage_update_money_show_financials_path(show), params: {
        show_financials: { revenue_type: "ticket_sales", ticket_sales_lines_attributes: {
          "0" => { id: tt.id, ticket_source_id: eventbrite.id, tickets_sold: "30", amount: "400" },
          "1" => { ticket_source_id: door.id, tickets_sold: "10", amount: "200" }
        } }
      }
      financials.reload
      expect(financials.ticket_sales_lines.map { |l| [ l.ticket_source.name, l.tickets_sold, l.amount.to_f ] })
        .to contain_exactly([ "Eventbrite", 30, 400.0 ], [ "At the door", 10, 200.0 ])
      expect(financials.ticket_count).to eq(40)
      expect(financials.ticket_revenue).to eq(600)

      door_line = financials.ticket_sales_lines.find_by(ticket_source: door)
      patch manage_update_money_show_financials_path(show), params: {
        show_financials: { revenue_type: "ticket_sales", ticket_sales_lines_attributes: {
          "0" => { id: tt.id, ticket_source_id: eventbrite.id, tickets_sold: "30", amount: "400" },
          "1" => { id: door_line.id, ticket_source_id: door.id, tickets_sold: "", amount: "" }
        } }
      }
      expect(financials.reload.ticket_sales_lines.map(&:ticket_source)).to eq([ eventbrite ])
      expect(financials.ticket_revenue).to eq(400)
    end

    it "shows the breakdown back on the financials page" do
      financials = show.create_show_financials!(revenue_type: "ticket_sales", data_confirmed: true)
      financials.ticket_sales_lines.create!(ticket_source: eventbrite, tickets_sold: 40, amount: 400)

      get manage_money_show_financials_path(show)

      expect(response.body).to include("Eventbrite")
      expect(response.body).to include("40 tickets")
    end
  end

  describe "an org that hasn't named any sources" do
    it "still takes the figures, on one unlabelled line" do
      patch manage_update_money_show_financials_path(show), params: {
        show_financials: {
          revenue_type: "ticket_sales",
          data_confirmed: "1",
          ticket_sales_lines_attributes: { "0" => { tickets_sold: "25", amount: "250.00" } }
        }
      }

      financials = show.reload.show_financials
      expect(financials.ticket_sales_lines.count).to eq(1)
      expect(financials.ticket_sales_lines.first.source_name).to eq("Ticket sales")
      expect(financials.ticket_count).to eq(25)
      expect(financials.ticket_revenue).to eq(250)
    end

    it "carries an older row's figures into its first line untouched" do
      show.create_show_financials!(revenue_type: "ticket_sales", ticket_count: 33, ticket_revenue: 330)

      get manage_money_show_financials_path(show)

      # The worksheet seeds a line from whatever was already there, so saving it
      # migrates the row and changes no number.
      expect(response.body).to include('value="33"')
      expect(response.body).to include('value="330.00"')
    end
  end

  # The whole point of keeping the two columns: a contract that settles off
  # ticket revenue must see exactly the same number whether it was entered as
  # one figure or split across sources.
  describe "settlement math" do
    let!(:contractor) { create(:contractor, organization: org, name: "Touring Co") }
    let!(:contract) do
      create(:contract, :active, organization: org, production: production, contractor: contractor,
                                 contractor_name: contractor.name,
                                 draft_data: { "payment_structure" => "revenue_share",
                                               "payment_config" => { "revenue_our_share" => 60,
                                                                     "revenue_their_share" => 40,
                                                                     "revenue_who_sells" => "us" } })
    end

    def night_net
      contract.reload.night_result(show.reload)&.dig(:net)
    end

    it "matches whether the money was entered as one figure or split by source" do
      financials = show.create_show_financials!(revenue_type: "ticket_sales", data_confirmed: true,
                                                ticket_count: 52, ticket_revenue: 544)
      one_figure = night_net
      expect(one_figure).to be_present

      source = org.ticket_sources.create!(name: "Eventbrite")
      financials.ticket_sales_lines.create!(ticket_source: source, tickets_sold: 40, amount: 400)
      financials.ticket_sales_lines.create!(tickets_sold: 12, amount: 144)

      expect(night_net).to eq(one_figure)
    end
  end
end
