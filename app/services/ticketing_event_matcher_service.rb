# frozen_string_literal: true

# Intelligent matching between RemoteTicketingEvents and Shows
# Uses name similarity and date proximity to find likely matches
class TicketingEventMatcherService
  # Confidence thresholds
  HIGH_CONFIDENCE = 0.85  # Auto-link without user confirmation
  MEDIUM_CONFIDENCE = 0.5 # Suggest but ask for confirmation
  LOW_CONFIDENCE = 0.3    # Show as possible match

  attr_reader :organization, :production

  def initialize(organization, production: nil)
    @organization = organization
    @production = production
  end

  # Run matching for all unlinked remote events in the organization
  def match_all_events
    results = { auto_linked: 0, needs_review: 0, no_match: 0 }

    unlinked_events.find_each do |remote_event|
      match = find_best_match(remote_event)

      if match[:confidence] >= HIGH_CONFIDENCE
        # Auto-link high confidence matches
        link_event_to_show(remote_event, match[:show], match[:confidence])
        results[:auto_linked] += 1
      elsif match[:confidence] >= LOW_CONFIDENCE
        # Store as suggested match for review
        remote_event.update!(
          suggested_show_id: match[:show].id,
          match_confidence: match[:confidence],
          match_reasons: match[:reasons]
        )
        results[:needs_review] += 1
      else
        results[:no_match] += 1
      end
    end

    results
  end

  # Find the best matching show for a remote event
  def find_best_match(remote_event)
    candidates = candidate_shows(remote_event)
    return { show: nil, confidence: 0, reasons: [] } if candidates.empty?

    scored = candidates.map do |show|
      score_match(remote_event, show)
    end

    scored.max_by { |m| m[:confidence] }
  end

  # Score how well a remote event matches a show
  def score_match(remote_event, show)
    scores = []
    reasons = []

    # Date matching (most important)
    date_score = score_date_match(remote_event, show)
    if date_score > 0
      scores << { weight: 0.5, score: date_score }
      reasons << "date_match" if date_score >= 0.9
      reasons << "date_close" if date_score >= 0.5 && date_score < 0.9
    end

    # Name similarity
    name_score = score_name_match(remote_event, show)
    if name_score > 0
      scores << { weight: 0.35, score: name_score }
      reasons << "name_match" if name_score >= 0.7
    end

    # Production name in event name
    prod_score = score_production_match(remote_event, show)
    if prod_score > 0
      scores << { weight: 0.15, score: prod_score }
      reasons << "production_match" if prod_score >= 0.7
    end

    # Calculate weighted confidence
    if scores.any?
      total_weight = scores.sum { |s| s[:weight] }
      confidence = scores.sum { |s| s[:weight] * s[:score] } / total_weight
    else
      confidence = 0
    end

    { show: show, confidence: confidence.round(3), reasons: reasons }
  end

  # Link an event to a show
  def link_event_to_show(remote_event, show, confidence = nil)
    remote_event.update!(
      show: show,
      production_ticketing_setup: show.production.production_ticketing_setup,
      match_confidence: confidence,
      suggested_show_id: nil # Clear suggestion since it's now linked
    )
  end

  # Unlink an event from a show
  def unlink_event(remote_event)
    remote_event.update!(
      show_id: nil,
      production_ticketing_setup_id: nil,
      match_confidence: nil
    )
  end

  # Get events that need human review
  def events_needing_review
    RemoteTicketingEvent
      .where(organization: organization)
      .where(show_id: nil)
      .where.not(suggested_show_id: nil)
      .where("match_confidence >= ? AND match_confidence < ?", LOW_CONFIDENCE, HIGH_CONFIDENCE)
      .includes(:ticketing_provider)
      .order(match_confidence: :desc)
  end

  # Get events with no match found
  def events_no_match
    RemoteTicketingEvent
      .where(organization: organization)
      .where(show_id: nil)
      .where(suggested_show_id: nil)
      .includes(:ticketing_provider)
      .order(event_date: :asc)
  end

  private

  def unlinked_events
    RemoteTicketingEvent
      .where(organization: organization)
      .where(show_id: nil)
      .where.not(remote_status: :canceled)
  end

  # Get shows that could potentially match this event
  def candidate_shows(remote_event)
    # Look for shows within 7 days of the event date
    return [] unless remote_event.event_date

    date_range = (remote_event.event_date - 7.days)..(remote_event.event_date + 7.days)

    scope = if production
      # Scoped to specific production
      production.shows
    else
      # All organization shows
      organization.shows
    end

    scope
      .where(date_and_time: date_range)
      .where(canceled: false)
      .includes(:production)
  end

  # Score date match (0-1)
  def score_date_match(remote_event, show)
    return 0 unless remote_event.event_date && show.date_and_time

    # Same day = 1.0
    # Within 1 hour = 0.95
    # Same day different time = 0.8
    # Within 1 day = 0.5
    # Within 7 days = 0.1

    diff_seconds = (remote_event.event_date - show.date_and_time).abs
    diff_hours = diff_seconds / 3600.0
    diff_days = diff_hours / 24.0

    if diff_seconds < 60 # Within 1 minute
      1.0
    elsif diff_hours <= 1
      0.95
    elsif diff_hours <= 4 # Same general time slot
      0.9
    elsif diff_days <= 1 && remote_event.event_date.to_date == show.date_and_time.to_date
      0.8
    elsif diff_days <= 1
      0.5
    elsif diff_days <= 3
      0.3
    elsif diff_days <= 7
      0.1
    else
      0
    end
  end

  # Score name similarity (0-1)
  def score_name_match(remote_event, show)
    return 0 unless remote_event.event_name && show.display_name

    event_name = normalize_name(remote_event.event_name)
    show_name = normalize_name(show.display_name)

    return 1.0 if event_name == show_name

    # Calculate Jaccard similarity of words
    event_words = event_name.split(/\s+/).to_set
    show_words = show_name.split(/\s+/).to_set

    return 0 if event_words.empty? || show_words.empty?

    intersection = event_words & show_words
    union = event_words | show_words

    jaccard = intersection.size.to_f / union.size

    # Also check if one contains the other
    contains_bonus = 0
    if event_name.include?(show_name) || show_name.include?(event_name)
      contains_bonus = 0.3
    end

    [ jaccard + contains_bonus, 1.0 ].min
  end

  # Score if production name appears in event name (0-1)
  def score_production_match(remote_event, show)
    return 0 unless remote_event.event_name && show.production

    event_name = normalize_name(remote_event.event_name)
    production_name = normalize_name(show.production.name)

    return 1.0 if event_name.include?(production_name)

    # Check for partial production name match
    prod_words = production_name.split(/\s+/)
    event_words = event_name.split(/\s+/).to_set

    matches = prod_words.count { |w| event_words.include?(w) }
    return 0 if prod_words.empty?

    matches.to_f / prod_words.size
  end

  # Normalize name for comparison
  def normalize_name(name)
    name.to_s
        .downcase
        .gsub(/[^\w\s]/, "") # Remove punctuation
        .gsub(/\s+/, " ")    # Normalize whitespace
        .strip
  end
end
