# frozen_string_literal: true

module Ticketing
  module Operations
    class MatchShows
      # Time tolerance for matching shows to provider occurrences
      MATCH_TOLERANCE = 2.hours

      attr_reader :production_link, :provider, :service

      def initialize(production_link)
        @production_link = production_link
        @provider = production_link.ticketing_provider
        @service = provider.service
      end

      # Analyze potential matches without applying them
      # Returns { matches: [], unmatched_shows: [], unmatched_occurrences: [] }
      def analyze
        occurrences = fetch_provider_occurrences
        our_shows = production_link.production.shows
          .where("date_and_time >= ?", 30.days.ago)
          .order(:date_and_time)
          .to_a

        # Already linked show IDs
        linked_show_ids = production_link.ticketing_show_links.pluck(:show_id)
        unlinked_shows = our_shows.reject { |s| linked_show_ids.include?(s.id) }

        # Already linked occurrence IDs
        linked_occurrence_ids = production_link.ticketing_show_links.pluck(:provider_occurrence_id)
        unlinked_occurrences = occurrences.reject { |o| linked_occurrence_ids.include?(occurrence_id(o)) }

        matches = []
        unmatched_shows = []

        unlinked_shows.each do |show|
          match = find_best_match(show, unlinked_occurrences)

          if match
            matches << {
              show: show,
              occurrence: match,
              occurrence_id: occurrence_id(match),
              occurrence_time: occurrence_time(match),
              confidence: calculate_confidence(show, match)
            }
            unlinked_occurrences.delete(match)
          else
            unmatched_shows << show
          end
        end

        {
          matches: matches,
          unmatched_shows: unmatched_shows,
          unmatched_occurrences: unlinked_occurrences.map { |o| normalize_occurrence(o) }
        }
      end

      # Apply the given matches, creating TicketingShowLink records
      def apply_matches!(match_data)
        applied = 0

        match_data.each do |match|
          show = match[:show] || Show.find(match[:show_id])
          occurrence_id = match[:occurrence_id]

          next if occurrence_id.blank?
          next if production_link.ticketing_show_links.exists?(show: show)

          TicketingShowLink.create!(
            show: show,
            ticketing_production_link: production_link,
            provider_occurrence_id: occurrence_id,
            provider_ticket_page_url: occurrence_url(match[:occurrence]),
            sync_status: "pending"
          )

          applied += 1
        end

        applied
      end

      # Auto-match and apply all high-confidence matches
      def auto_match!
        analysis = analyze

        # Only apply high-confidence matches (exact time match)
        high_confidence = analysis[:matches].select { |m| m[:confidence] >= 0.9 }

        {
          applied: apply_matches!(high_confidence),
          total_matches: analysis[:matches].size,
          unmatched_shows: analysis[:unmatched_shows].size,
          unmatched_occurrences: analysis[:unmatched_occurrences].size
        }
      end

      private

      def fetch_provider_occurrences
        response = service.fetch_occurrences(production_link.provider_event_id)

        # Handle paginated responses
        case provider.provider_type
        when "ticket_tailor"
          response["data"] || []
        when "eventbrite"
          response["events"] || []
        else
          response["data"] || response["events"] || response["occurrences"] || []
        end
      end

      def find_best_match(show, occurrences)
        occurrences.find do |occ|
          time = occurrence_time(occ)
          next false unless time

          (show.date_and_time - time).abs < MATCH_TOLERANCE
        end
      end

      def calculate_confidence(show, occurrence)
        time = occurrence_time(occurrence)
        return 0 unless time

        diff = (show.date_and_time - time).abs

        if diff < 1.minute
          1.0
        elsif diff < 15.minutes
          0.95
        elsif diff < 1.hour
          0.8
        else
          0.6
        end
      end

      def occurrence_id(occ)
        occ["id"] || occ["event_id"]
      end

      def occurrence_time(occ)
        # Handle different provider formats
        time_value = occ["start"] || occ["start_at"] || occ.dig("start", "utc") || occ["datetime"]
        return nil unless time_value

        if time_value.is_a?(Hash)
          parsed_value = time_value["utc"] || time_value["local"]
          return nil unless parsed_value

          Time.zone.parse(parsed_value)
        else
          Time.zone.parse(time_value.to_s)
        end
      rescue ArgumentError, TypeError
        nil
      end

      def occurrence_url(occ)
        return nil unless occ

        occ["url"] || occ["ticket_url"] || occ.dig("online_event", "url")
      end

      def normalize_occurrence(occ)
        {
          id: occurrence_id(occ),
          time: occurrence_time(occ),
          name: occ["name"] || occ["title"],
          url: occurrence_url(occ),
          status: occ["status"],
          tickets_available: occ["tickets_available"],
          tickets_issued: occ["tickets_issued"] || occ["tickets_sold"]
        }
      end
    end
  end
end
