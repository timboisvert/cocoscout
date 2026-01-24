# frozen_string_literal: true

module Ticketing
  class ServiceFactory
    PROVIDERS = {
      "ticket_tailor" => "Ticketing::Providers::TicketTailorService",
      "eventbrite" => "Ticketing::Providers::EventbriteService",
      "wix" => "Ticketing::Providers::WixService",
      "seat_engine" => "Ticketing::Providers::SeatEngineService",
      "square" => "Ticketing::Providers::SquareService"
    }.freeze

    PROVIDER_INFO = {
      "ticket_tailor" => {
        id: "ticket_tailor",
        name: "Ticket Tailor",
        description: "Modern ticketing platform with robust API and real-time webhooks.",
        status: "available",
        help_url: "https://help.tickettailor.com/en/articles/4501841-getting-your-api-key",
        required_permissions: "Your API key needs Event read-only and Order read-only permissions. You can create a key with these roles in Box Office → API Keys."
      },
      "eventbrite" => {
        id: "eventbrite",
        name: "Eventbrite",
        description: "Global event platform with extensive event management features.",
        status: "coming_soon",
        help_url: "https://www.eventbrite.com/platform/api-keys",
        required_permissions: nil
      },
      "wix" => {
        id: "wix",
        name: "Wix Events",
        description: "Event ticketing integrated with Wix websites.",
        status: "coming_soon",
        help_url: nil,
        required_permissions: nil
      },
      "seat_engine" => {
        id: "seat_engine",
        name: "Seat Engine",
        description: "Theater and performing arts ticketing platform.",
        status: "coming_soon",
        help_url: nil,
        required_permissions: nil
      },
      "square" => {
        id: "square",
        name: "Square",
        description: "Point of sale and payment processing for events.",
        status: "coming_soon",
        help_url: nil,
        required_permissions: nil
      }
    }.freeze

    class << self
      def build(provider)
        service_class_name = PROVIDERS[provider.provider_type]
        raise "Unknown provider type: #{provider.provider_type}" unless service_class_name

        service_class_name.constantize.new(provider)
      end

      def available_providers
        # Return only providers that are available (not coming_soon)
        PROVIDER_INFO.values.select { |p| p[:status] == "available" } +
          PROVIDER_INFO.values.select { |p| p[:status] == "coming_soon" }
      end

      def provider_info(type)
        PROVIDER_INFO[type]
      end

      def provider_display_name(type)
        PROVIDER_INFO.dig(type, :name) || type.titleize
      end

      def provider_logo_path(type)
        "ticketing/#{type}.svg"
      end
    end
  end
end
