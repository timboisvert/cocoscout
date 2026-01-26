# frozen_string_literal: true

module Ticketing
  module Operations
    class AutoLinkEvents
      # Minimum confidence to auto-link without user confirmation
      AUTO_LINK_THRESHOLD = 0.85

      # Minimum confidence to suggest a match (below this, no suggestion)
      SUGGESTION_THRESHOLD = 0.5

      attr_reader :provider, :service

      def initialize(provider)
        @provider = provider
        @service = provider.service
      end

      # Fetch events from provider and auto-link/create pending records
      # Returns { linked: [], pending: [], errors: [] }
      def call
        results = { linked: [], pending: [], updated: [], errors: [] }

        begin
          provider_events = fetch_provider_events
        rescue StandardError => e
          results[:errors] << "Failed to fetch events: #{e.message}"
          return results
        end

        provider_events.each do |event|
          process_event(event, results)
        rescue StandardError => e
          results[:errors] << "Error processing event #{event[:id]}: #{e.message}"
        end

        results
      end

      private

      def fetch_provider_events
        response = service.fetch_events
        normalize_events(response)
      end

      def normalize_events(response)
        events = case provider.provider_type
                 when "ticket_tailor"
                   response["data"] || []
                 when "eventbrite"
                   response["events"] || []
                 else
                   response["data"] || response["events"] || []
                 end

        events.map { |e| normalize_event(e) }
      end

      def normalize_event(event)
        case provider.provider_type
        when "ticket_tailor"
          {
            id: event["id"],
            name: event["name"],
            status: event["status"],
            url: event["url"],
            occurrence_count: event.dig("total_occurrences") || event.dig("events", "total") || 0,
            first_date: parse_date(event["first_date"]),
            last_date: parse_date(event["last_date"]),
            raw: event
          }
        else
          {
            id: event["id"],
            name: event["name"] || event.dig("name", "text"),
            status: event["status"],
            url: event["url"],
            occurrence_count: 1,
            first_date: parse_date(event["start"]),
            last_date: parse_date(event["end"]),
            raw: event
          }
        end
      end

      def parse_date(value)
        return nil if value.blank?

        if value.is_a?(Hash)
          Time.zone.parse(value["utc"] || value["local"] || value["date"])
        else
          Time.zone.parse(value.to_s)
        end
      rescue ArgumentError
        nil
      end

      def process_event(event, results)
        # Check if already linked
        existing_link = provider.ticketing_production_links.find_by(provider_event_id: event[:id])
        if existing_link
          # Update event name if changed
          if existing_link.provider_event_name != event[:name]
            existing_link.update!(provider_event_name: event[:name])
            results[:updated] << { event: event, link: existing_link }
          end
          return
        end

        # Check if already in pending
        existing_pending = provider.ticketing_pending_events.find_by(provider_event_id: event[:id])
        if existing_pending
          update_pending_event(existing_pending, event, results)
          return
        end

        # Try to find a matching production
        match = find_best_production_match(event)

        if match && match[:confidence] >= AUTO_LINK_THRESHOLD
          # High confidence - auto-link
          create_auto_link(event, match, results)
        else
          # Low/no confidence - create pending event
          create_pending_event(event, match, results)
        end
      end

      def find_best_production_match(event)
        productions = provider.organization.productions
                              .where("created_at > ?", 2.years.ago)
                              .includes(:shows)

        best_match = nil
        best_confidence = 0

        productions.each do |production|
          confidence = calculate_match_confidence(event, production)

          if confidence > best_confidence
            best_confidence = confidence
            best_match = { production: production, confidence: confidence }
          end
        end

        return nil if best_confidence < SUGGESTION_THRESHOLD

        best_match
      end

      def calculate_match_confidence(event, production)
        scores = []

        # Name similarity (0-1)
        name_score = name_similarity(event[:name], production.name)
        scores << { weight: 0.6, score: name_score }

        # Date overlap (0-1)
        date_score = date_overlap_score(event, production)
        scores << { weight: 0.4, score: date_score }

        # Weighted average
        total_weight = scores.sum { |s| s[:weight] }
        scores.sum { |s| s[:weight] * s[:score] } / total_weight
      end

      def name_similarity(name1, name2)
        return 0 if name1.blank? || name2.blank?

        # Normalize names
        n1 = normalize_name(name1)
        n2 = normalize_name(name2)

        # Exact match
        return 1.0 if n1 == n2

        # Check if one contains the other
        return 0.9 if n1.include?(n2) || n2.include?(n1)

        # Word overlap
        words1 = n1.split(/\s+/).to_set
        words2 = n2.split(/\s+/).to_set

        return 0 if words1.empty? || words2.empty?

        intersection = (words1 & words2).size
        union = (words1 | words2).size

        # Jaccard similarity
        intersection.to_f / union
      end

      def normalize_name(name)
        name.downcase
            .gsub(/[^\w\s]/, "") # Remove punctuation
            .gsub(/\s+/, " ")    # Normalize whitespace
            .strip
      end

      def date_overlap_score(event, production)
        event_start = event[:first_date]
        event_end = event[:last_date] || event_start

        return 0 if event_start.nil?

        # Get production date range from shows
        shows = production.shows.where("date_and_time > ?", 1.year.ago)
        return 0 if shows.empty?

        prod_start = shows.minimum(:date_and_time)
        prod_end = shows.maximum(:date_and_time)

        return 0 if prod_start.nil?

        # Check for overlap
        # Event range: [event_start, event_end]
        # Production range: [prod_start, prod_end]

        # No overlap
        return 0 if event_end && event_end < prod_start - 7.days
        return 0 if prod_end && event_start > prod_end + 7.days

        # Calculate overlap percentage
        overlap_start = [event_start, prod_start].max
        overlap_end = [event_end || event_start, prod_end || prod_start].min

        return 0 if overlap_start > overlap_end

        # Perfect overlap or close enough
        event_duration = [(event_end || event_start) - event_start, 1.day].max
        overlap_duration = [overlap_end - overlap_start, 1.day].max

        [overlap_duration / event_duration, 1.0].min
      end

      def create_auto_link(event, match, results)
        link = provider.ticketing_production_links.create!(
          production: match[:production],
          provider_event_id: event[:id],
          provider_event_name: event[:name],
          provider_event_url: event[:url],
          provider_event_data: event[:raw],
          sync_enabled: true,
          sync_ticket_sales: true
        )

        # Auto-match shows to occurrences
        matcher = MatchShows.new(link)
        matcher.auto_match!

        results[:linked] << {
          event: event,
          production: match[:production],
          confidence: match[:confidence],
          link: link
        }

        # Log the auto-link
        Rails.logger.info(
          "Auto-linked Ticket Tailor event '#{event[:name]}' to production '#{match[:production].name}' " \
          "with #{(match[:confidence] * 100).round}% confidence"
        )
      end

      def create_pending_event(event, match, results)
        pending = provider.ticketing_pending_events.create!(
          provider_event_id: event[:id],
          provider_event_name: event[:name],
          provider_event_data: event[:raw],
          occurrence_count: event[:occurrence_count] || 0,
          first_occurrence_at: event[:first_date],
          last_occurrence_at: event[:last_date],
          status: "pending",
          suggested_production: match&.dig(:production),
          match_confidence: match&.dig(:confidence)
        )

        results[:pending] << {
          event: event,
          pending: pending,
          suggested_production: match&.dig(:production),
          confidence: match&.dig(:confidence)
        }
      end

      def update_pending_event(pending, event, results)
        # Update with fresh data from provider
        pending.update!(
          provider_event_name: event[:name],
          provider_event_data: event[:raw],
          occurrence_count: event[:occurrence_count] || 0,
          first_occurrence_at: event[:first_date],
          last_occurrence_at: event[:last_date]
        )

        # Re-check for matches if still pending
        if pending.status == "pending"
          match = find_best_production_match(event)

          if match && match[:confidence] >= AUTO_LINK_THRESHOLD
            # Now we have a high confidence match - auto-link
            link = pending.match_to_production!(match[:production])

            # Auto-match shows
            matcher = MatchShows.new(link)
            matcher.auto_match!

            results[:linked] << {
              event: event,
              production: match[:production],
              confidence: match[:confidence],
              link: link
            }
          elsif match
            # Update suggestion
            pending.update!(
              suggested_production: match[:production],
              match_confidence: match[:confidence]
            )
            results[:updated] << { event: event, pending: pending }
          end
        end
      end
    end
  end
end
