# frozen_string_literal: true

module TicketingAdapters
  # Adapter for manual/no-API providers
  # This is used when ticketing is handled externally with no API integration
  class ManualAdapter < BaseAdapter
    # Manual provider has no API capabilities
    CAPABILITIES = {
      "api_create_event" => false,
      "api_update_event" => false,
      "api_sync_inventory" => false,
      "api_fetch_sales" => false,
      "webhook_sales" => false,
      "webhook_inventory" => false,
      "webhook_event_updates" => false,
      "requires_approval" => false,
      "supports_draft" => false
    }.freeze

    # No required fields for manual - user just confirms the listing
    def required_fields
      {
        show_name: ->(listing) { listing.show_ticketing.show.display_name.present? },
        show_date: ->(listing) { listing.show_ticketing.show.date_and_time.present? }
      }
    end

    def test_connection
      { success: true, message: "Manual provider - no connection needed" }
    end

    def create_event(_listing)
      { success: false, error: "Manual provider - create listing externally and mark as complete" }
    end

    def update_event(_listing)
      { success: false, error: "Manual provider - update listing externally" }
    end

    def update_inventory(_listing)
      { success: false, error: "Manual provider - update inventory externally" }
    end

    def fetch_sales(_listing)
      { success: false, error: "Manual provider - enter sales manually or import CSV" }
    end

    def sync_listing(_listing)
      { success: false, error: "Manual provider - sync not available" }
    end

    # Generate instructions for manual listing
    def generate_listing_instructions(listing)
      show = listing.show_ticketing.show
      tiers = listing.show_ticketing.show_ticket_tiers

      <<~INSTRUCTIONS
        == LISTING DETAILS FOR #{provider.name.upcase} ==

        Event Name: #{show.display_name}
        Date: #{show.date_and_time.strftime("%A, %B %d, %Y at %I:%M %p")}
        #{show.end_time ? "End Time: #{show.end_time.strftime("%I:%M %p")}" : ""}

        #{show.location ? "Venue: #{show.location.name}\nAddress: #{show.location.full_address}" : "Online Event"}

        Description:
        #{show.description || "(No description)"}

        == TICKET TIERS ==
        #{tiers.map { |t| "- #{t.name}: $#{t.default_price_cents / 100.0} (#{t.available} available)" }.join("\n")}

        == AFTER LISTING ==
        Once you've created this listing on #{provider.name}, come back and:
        1. Click "Mark as Listed"
        2. Paste the ticket purchase URL
        3. (Optional) Add any notes about the listing

      INSTRUCTIONS
    end

    # Generate a shareable request that can be emailed
    def generate_listing_request_email(listing, recipient_name: nil)
      show = listing.show_ticketing.show
      org = provider.organization

      {
        subject: "Ticket Listing Request: #{show.display_name}",
        body: <<~EMAIL
          Hi#{recipient_name ? " #{recipient_name}" : ""},

          We'd like to request a ticket listing for the following event:

          #{generate_listing_instructions(listing)}

          Please let us know once the listing is live so we can link to it.

          Thanks,
          #{org.name}
        EMAIL
      }
    end
  end
end
