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

    DISPLAY_NAMES = {
      "ticket_tailor" => "Ticket Tailor",
      "eventbrite" => "Eventbrite",
      "wix" => "Wix Events",
      "seat_engine" => "Seat Engine",
      "square" => "Square"
    }.freeze

    class << self
      def build(provider)
        service_class_name = PROVIDERS[provider.provider_type]
        raise "Unknown provider type: #{provider.provider_type}" unless service_class_name

        service_class_name.constantize.new(provider)
      end

      def available_providers
        PROVIDERS.keys
      end

      def provider_display_name(type)
        DISPLAY_NAMES[type] || type.titleize
      end

      def provider_logo_path(type)
        "ticketing/#{type}.svg"
      end
    end
  end
end
