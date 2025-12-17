# frozen_string_literal: true

module CalendarSync
  class BaseService
    attr_reader :subscription

    def initialize(subscription)
      @subscription = subscription
    end

    # Create an event in the calendar
    def create_event(show)
      raise NotImplementedError, "Subclasses must implement #create_event"
    end

    # Update an existing event
    def update_event(calendar_event)
      raise NotImplementedError, "Subclasses must implement #update_event"
    end

    # Delete an event
    def delete_event(calendar_event)
      raise NotImplementedError, "Subclasses must implement #delete_event"
    end

    # Sync all events for the subscription
    def sync_all
      return unless subscription.enabled?

      shows = subscription.shows_to_sync
      existing_events = subscription.calendar_events.includes(:show).index_by(&:show_id)

      # Create or update events for current shows
      shows.find_each do |show|
        if existing_events[show.id]
          calendar_event = existing_events[show.id]
          update_event(calendar_event) if calendar_event.show_changed?
          existing_events.delete(show.id)
        else
          create_event(show)
        end
      end

      # Delete events for shows that are no longer in scope
      existing_events.values.each do |calendar_event|
        delete_event(calendar_event)
      end

      subscription.mark_synced!
    rescue StandardError => e
      subscription.mark_sync_error!(e.message)
      Rails.logger.error("Calendar sync failed for subscription #{subscription.id}: #{e.message}")
      raise
    end

    protected

    def event_title(show)
      title_parts = [ show.production.name ]
      title_parts << show.event_type.titleize if show.event_type.present?
      title_parts << show.secondary_name if show.secondary_name.present?
      title_parts.join(" - ")
    end

    def event_description(show)
      parts = []
      parts << show.production.name
      parts << "Event Type: #{show.event_type.titleize}" if show.event_type.present?
      parts << show.secondary_name if show.secondary_name.present?

      if show.is_online?
        parts << "Online Event"
        parts << show.online_location_info if show.online_location_info.present?
      end

      parts.join("\n\n")
    end

    def event_location(show)
      return show.online_location_info.presence || "Online" if show.is_online? && show.location.blank?

      show.location&.full_address
    end

    def event_start_time(show)
      show.date_and_time
    end

    def event_end_time(show)
      # Default to 2 hours if no end time
      show.date_and_time + 2.hours
    end
  end
end
