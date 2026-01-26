# frozen_string_literal: true

module Manage
  class TicketingPendingEventsController < ManageController
    before_action :ensure_user_is_manager
    before_action :set_pending_event, only: [:show, :link, :dismiss]

    def index
      @pending_events = TicketingPendingEvent
        .joins(:ticketing_provider)
        .where(ticketing_providers: { organization_id: Current.organization.id })
        .pending
        .includes(:ticketing_provider, :suggested_production)
        .order(created_at: :desc)

      @dismissed_events = TicketingPendingEvent
        .joins(:ticketing_provider)
        .where(ticketing_providers: { organization_id: Current.organization.id })
        .where(status: "dismissed")
        .includes(:ticketing_provider)
        .order(dismissed_at: :desc)
        .limit(10)
    end

    def show
      @productions = Current.organization.productions.order(:name)

      # Calculate match scores for all productions if not already suggested
      @production_scores = @productions.map do |production|
        score = calculate_match_score(@pending_event, production)
        { production: production, score: score }
      end.sort_by { |p| -p[:score] }
    end

    def link
      production = Current.organization.productions.find(params[:production_id])

      link = @pending_event.match_to_production!(production, user: Current.user)

      # Auto-match shows to occurrences
      matcher = Ticketing::Operations::MatchShows.new(link)
      result = matcher.auto_match!

      if result[:applied] > 0
        redirect_to manage_money_ticketing_production_link_path(production, link),
                    notice: "Linked '#{@pending_event.provider_event_name}' to #{production.name}. #{result[:applied]} shows matched automatically."
      else
        redirect_to match_manage_money_ticketing_production_link_path(production, link),
                    notice: "Linked to #{production.name}. Review show matches to start syncing."
      end
    rescue ActiveRecord::RecordInvalid => e
      redirect_to manage_ticketing_pending_event_path(@pending_event),
                  alert: "Failed to link: #{e.message}"
    rescue StandardError => e
      redirect_to manage_ticketing_pending_event_path(@pending_event),
                  alert: "Error: #{e.class.name} - #{e.message}"
    end

    def dismiss
      @pending_event.dismiss!(Current.user)
      redirect_to manage_ticketing_pending_events_path,
                  notice: "'#{@pending_event.provider_event_name}' dismissed."
    end

    def sync_now
      provider = Current.organization.ticketing_providers.find(params[:provider_id])

      # Run sync in background
      TicketingSyncJob.perform_later(provider.id, sync_type: :events_only)

      redirect_to manage_organization_path(Current.organization, anchor: "tab-4"),
                  notice: "Syncing events from #{provider.name}. New events will appear shortly."
    end

    private

    def set_pending_event
      @pending_event = TicketingPendingEvent
        .joins(:ticketing_provider)
        .where(ticketing_providers: { organization_id: Current.organization.id })
        .find(params[:id])
    end

    def calculate_match_score(pending_event, production)
      scores = []

      # Name similarity
      if pending_event.provider_event_name.present? && production.name.present?
        name_score = name_similarity(pending_event.provider_event_name, production.name)
        scores << { weight: 0.6, score: name_score }
      end

      # Date overlap
      if pending_event.first_occurrence_at.present?
        date_score = date_overlap_score(pending_event, production)
        scores << { weight: 0.4, score: date_score }
      end

      return 0 if scores.empty?

      total_weight = scores.sum { |s| s[:weight] }
      scores.sum { |s| s[:weight] * s[:score] } / total_weight
    end

    def name_similarity(name1, name2)
      n1 = normalize_name(name1)
      n2 = normalize_name(name2)

      return 1.0 if n1 == n2
      return 0.9 if n1.include?(n2) || n2.include?(n1)

      words1 = n1.split(/\s+/).to_set
      words2 = n2.split(/\s+/).to_set

      return 0 if words1.empty? || words2.empty?

      intersection = (words1 & words2).size
      union = (words1 | words2).size

      intersection.to_f / union
    end

    def normalize_name(name)
      name.downcase.gsub(/[^\w\s]/, "").gsub(/\s+/, " ").strip
    end

    def date_overlap_score(pending_event, production)
      event_start = pending_event.first_occurrence_at
      event_end = pending_event.last_occurrence_at || event_start

      shows = production.shows.where("date_and_time > ?", 1.year.ago)
      return 0 if shows.empty?

      prod_start = shows.minimum(:date_and_time)
      prod_end = shows.maximum(:date_and_time)

      return 0 if prod_start.nil?
      return 0 if event_end && event_end < prod_start - 7.days
      return 0 if prod_end && event_start > prod_end + 7.days

      1.0
    end
  end
end
