# frozen_string_literal: true

# ProviderEvent represents the provider's concept of an "event" or "series" -
# which maps to our Production concept. This is a cache of what exists on
# the provider's platform, from their perspective.
#
# Provider hierarchy:
#   TicketingProvider → ProviderEvent (series/event) → RemoteTicketingEvent (occurrences)
#
# CocoScout mapping:
#   ProviderEvent maps to → Production
#   RemoteTicketingEvent maps to → Show
#
class ProviderEvent < ApplicationRecord
  # ============================================
  # Associations
  # ============================================

  belongs_to :ticketing_provider
  belongs_to :organization
  belongs_to :production, optional: true

  has_many :remote_ticketing_events, dependent: :destroy

  # ============================================
  # Enums
  # ============================================

  enum :match_status, {
    unmatched: "unmatched",      # No production linked yet
    suggested: "suggested",      # Auto-matched with confidence score
    confirmed: "confirmed",      # User confirmed the match
    ignored: "ignored",          # User chose to ignore this event
    no_match: "no_match"         # Explicitly marked as having no CocoScout equivalent
  }, prefix: true

  enum :status, {
    active: "active",
    completed: "completed",
    canceled: "canceled"
  }, prefix: true, default: :active

  # ============================================
  # Validations
  # ============================================

  validates :external_event_id, presence: true
  validates :external_event_id, uniqueness: { scope: :ticketing_provider_id }

  # ============================================
  # Scopes
  # ============================================

  scope :needs_attention, -> { where(match_status: %w[unmatched suggested]) }
  scope :mapped, -> { where(match_status: %w[suggested confirmed]).where.not(production_id: nil) }
  scope :unmapped, -> { where(production_id: nil) }

  # ============================================
  # Instance Methods
  # ============================================

  def occurrence_count
    remote_ticketing_events.count
  end

  def upcoming_occurrences
    remote_ticketing_events.where("event_date >= ?", Time.current).order(:event_date)
  end

  def date_range
    dates = remote_ticketing_events.pluck(:event_date).compact
    return nil if dates.empty?

    [ dates.min, dates.max ]
  end

  # Suggest a production match based on name similarity
  # Strategy:
  # 1. Try exact match on Production name
  # 2. Try fuzzy match on Production name
  # 3. Try exact/fuzzy match on Show display_name (provider may have separate events per show)
  # 4. Try partial match (provider name contains production name or vice versa)
  def suggest_production_match!
    return if match_status_confirmed? || production_id.present?

    normalized_name = normalize_for_matching(name)
    return if normalized_name.blank?

    best_match = nil
    best_score = 0
    match_source = nil # :production or :show

    # First pass: Match against Production names
    organization.productions.find_each do |production|
      prod_normalized = normalize_for_matching(production.name)
      next if prod_normalized.blank?

      # Exact match on production
      if normalized_name == prod_normalized
        best_match = production
        best_score = 1.0
        match_source = :production
        break
      end

      # Fuzzy match on production
      score = calculate_similarity(normalized_name, prod_normalized)
      if score > best_score && score >= 0.7
        best_match = production
        best_score = score
        match_source = :production
      end

      # Check if provider name contains production name (e.g., "Space Jam: Laugh-Along, Live!" contains "Laugh-Along, Live!")
      if prod_normalized.length >= 5 && normalized_name.include?(prod_normalized)
        containment_score = prod_normalized.length.to_f / normalized_name.length
        # Boost score for longer matches
        adjusted_score = 0.7 + (containment_score * 0.25)
        if adjusted_score > best_score
          best_match = production
          best_score = adjusted_score
          match_source = :production_contained
        end
      end
    end

    # Second pass: If no good production match, try matching against Show display_names
    # This handles cases where provider has separate events for each show in a production
    if best_score < 0.85
      Show.joins(:production).where(productions: { organization_id: organization_id }).includes(:production).find_each do |show|
        show_normalized = normalize_for_matching(show.display_name)
        next if show_normalized.blank?

        # Exact match on show name
        if normalized_name == show_normalized
          if show.production && (!best_match || best_score < 1.0)
            best_match = show.production
            best_score = 1.0
            match_source = :show
          end
          break
        end

        # Fuzzy match on show name
        score = calculate_similarity(normalized_name, show_normalized)
        if score > best_score && score >= 0.75
          if show.production
            best_match = show.production
            best_score = score
            match_source = :show
          end
        end
      end
    end

    if best_match
      # Auto-confirm high-confidence matches
      new_status = if best_score >= 0.95 && match_source == :production
        :confirmed
      elsif best_score >= 1.0 && match_source == :show
        :confirmed
      else
        :suggested
      end

      update!(
        production: best_match,
        match_status: new_status,
        match_confidence: best_score
      )
    end
  end

  def confirm_match!(production)
    update!(
      production: production,
      match_status: :confirmed,
      match_confidence: 1.0
    )
  end

  def clear_match!
    update!(
      production: nil,
      match_status: :unmatched,
      match_confidence: nil
    )
  end

  def ignore!
    update!(match_status: :ignored)
  end

  private

  # Normalize name for matching: lowercase, remove punctuation, collapse whitespace
  def normalize_for_matching(str)
    return "" if str.blank?

    str.downcase
       .gsub(/[^\w\s]/, " ")  # Replace punctuation with spaces
       .gsub(/\s+/, " ")      # Collapse whitespace
       .strip
  end

  # Calculate similarity between two normalized strings
  def calculate_similarity(str1, str2)
    return 1.0 if str1 == str2
    return 0.0 if str1.blank? || str2.blank?

    # Use Jaro-Winkler-like approach: token overlap
    tokens1 = str1.split
    tokens2 = str2.split

    return 0.0 if tokens1.empty? || tokens2.empty?

    # Count matching tokens
    matching = (tokens1 & tokens2).size
    total = [ tokens1.size, tokens2.size ].max

    # Base score from token overlap
    token_score = matching.to_f / total

    # Bonus for same token count and order
    if tokens1.size == tokens2.size
      # Check how many are in the same position
      positional_matches = tokens1.zip(tokens2).count { |a, b| a == b }
      positional_score = positional_matches.to_f / tokens1.size
      token_score = (token_score + positional_score) / 2.0
    end

    token_score
  end
end
