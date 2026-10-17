# frozen_string_literal: true

# The letters that stand in for a missing poster or headshot: at most two,
# the first letter of the first two words that carry the name, with articles
# and little words dropped. "The Rocky Horror Picture Show" reads "RH",
# "Mary Jane Van Der Berg" reads "MJ", "Hags" reads "H". Two letters is what
# people recognize from every avatar they've seen, and two never overflow a
# small box (Tim, 2026-10-17: five letters spilling out of a 48px poster
# "looks like shit").
module Monogram
  extend ActiveSupport::Concern

  LITTLE_WORDS = %w[a an the of and or for to in on at by with o n].freeze

  def initials
    words = name.to_s.split
    kept = words.reject do |word|
      bare = word.downcase.gsub(/[^[:alnum:]]/, "")
      bare.blank? || LITTLE_WORDS.include?(bare)
    end
    (kept.presence || words).first(2).map { |word| word[0] }.join.upcase
  end
end
