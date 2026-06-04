# frozen_string_literal: true

# Find-or-add venues. The mic submission flow and "move to a different
# venue" flow both go through here so we don't keep generating dupe
# venues when someone types "Cole's Bar" while one already exists as
# "Coles Bar". Lookup is case + apostrophe + whitespace insensitive
# and returns the top 8 candidates so the UI can show them inline.
module Mics
  class VenuesController < BaseController
    # JSON: top 8 fuzzy matches against an input string. Always 200,
    # never 404 — empty results are valid.
    def lookup
      q = params[:q].to_s
      norm = normalize(q)
      results = if norm.length < 2
        []
      else
        like = "%#{q.downcase.strip}%"
        rough_matches = Venue.where(
          "LOWER(name) LIKE :like OR LOWER(city) LIKE :like",
          like: like
        ).limit(40)

        # Refine in Ruby with the same normalization the user typed
        # against, so apostrophe / whitespace / case variants score.
        rough_matches
          .map { |v| [ v, score_match(v, norm) ] }
          .reject { |(_, s)| s.zero? }
          .sort_by { |(v, s)| [ -s, v.name.to_s.downcase ] }
          .first(8)
          .map { |(v, _)| serialize(v) }
      end

      render json: { results: results }
    end

    # POST: create a venue from the new-mic submission flow's modal.
    # Used by the find-or-add Stimulus controller when the user
    # accepts the "I really do want a new venue" path.
    def create
      v = Venue.new(venue_params)
      v.country ||= "US"
      if v.save
        render json: { ok: true, venue: serialize(v) }
      else
        render json: { ok: false, errors: v.errors.full_messages }, status: :unprocessable_content
      end
    end

    private

    def venue_params
      params.require(:venue).permit(:name, :address1, :address2, :city, :state, :postal_code, :neighborhood)
    end

    # Lowercase + strip apostrophes + collapse whitespace so "Cole's"
    # matches "coles" matches "Cole 's".
    def normalize(s)
      s.to_s.downcase.gsub(/[‘’']/, "").gsub(/\s+/, " ").strip
    end

    # Crude rank — startswith beats contains; multi-word matches stack.
    def score_match(venue, query_norm)
      name_norm = normalize(venue.name)
      return 0 if name_norm.blank?
      if name_norm == query_norm
        100
      elsif name_norm.start_with?(query_norm)
        50
      elsif name_norm.include?(query_norm)
        25
      else
        query_norm.split.count { |w| name_norm.include?(w) }
      end
    end

    def serialize(venue)
      {
        id:           venue.id,
        name:         venue.name,
        address1:     venue.address1,
        neighborhood: venue.neighborhood,
        city:         venue.city,
        state:        venue.state,
        postal_code:  venue.postal_code,
        mic_count:    venue.mics.count
      }
    end
  end
end
