# frozen_string_literal: true

module EventLinkageHelper
  # Groups shows into linked groups and standalone shows
  # Returns an array of items where each item is either:
  #   - { type: :linkage, event_linkage: EventLinkage, shows: [...], entity_key: String, entity: Object }
  #   - { type: :show, show: Show, entity_key: String, entity: Object }
  #
  # Shows are grouped by event_linkage_id. Linked shows appear once per linkage,
  # sorted by the first show's date. Unlinked shows appear individually.
  def group_shows_with_linkages(shows, entity_key:, entity:)
    return [] if shows.blank?

    result = []
    seen_linkage_ids = Set.new

    # Sort shows by date first
    sorted_shows = shows.sort_by(&:date_and_time)

    sorted_shows.each do |show|
      if show.event_linkage_id.present?
        # Skip if we've already added this linkage
        next if seen_linkage_ids.include?(show.event_linkage_id)

        seen_linkage_ids.add(show.event_linkage_id)

        # Find all shows in this linkage from the original list
        linkage_shows = sorted_shows.select { |s| s.event_linkage_id == show.event_linkage_id }

        result << {
          type: :linkage,
          event_linkage: show.event_linkage,
          shows: linkage_shows.sort_by(&:date_and_time),
          entity_key: entity_key,
          entity: entity,
          first_date: linkage_shows.map(&:date_and_time).min
        }
      else
        # Standalone show
        result << {
          type: :show,
          show: show,
          entity_key: entity_key,
          entity: entity,
          first_date: show.date_and_time
        }
      end
    end

    # Sort by first date
    result.sort_by { |item| item[:first_date] }
  end

  # Build availabilities hash for a linkage from entity's availability data
  # Returns { show_id => ShowAvailability }
  def linkage_availabilities(linkage_shows, availabilities_hash)
    result = {}
    linkage_shows.each do |show|
      result[show.id] = availabilities_hash[show.id]
    end
    result
  end

  # Check if all shows in a linkage are awaiting response (no availability set)
  def linkage_awaiting_response?(linkage_shows, availabilities_hash)
    linkage_shows.all? { |show| availabilities_hash[show.id].nil? }
  end

  # Check if any shows in a linkage are awaiting response
  def linkage_has_pending?(linkage_shows, availabilities_hash)
    linkage_shows.any? { |show| availabilities_hash[show.id].nil? }
  end
end
