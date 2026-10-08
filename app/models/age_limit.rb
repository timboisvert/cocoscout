# frozen_string_literal: true

# A show's minimum age, in words, and the choice that sets it (Tim,
# 2026-10-07). A production sets one for all its dates (blank: all ages); a
# date can set its own, all ages included, when it differs
# (TicketListing#effective_minimum_age). The ticket page, checkout, the
# buyer's order page, their emails and the door all say it these ways.
module AgeLimit
  PRESETS = [ 18, 21, 25 ].freeze
  AGES = (1..99)
  INHERIT = "production"
  ALL_AGES = "all"
  OTHER = "other"

  # "Ages 21 and over".
  def self.words(age)
    "Ages #{age} and over" if age.to_i.positive?
  end

  # "21 and over", under a label that already says Ages.
  def self.label(age)
    "#{age} and over" if age.to_i.positive?
  end

  # "21+", for tight spots.
  def self.short(age)
    "#{age}+" if age.to_i.positive?
  end

  # The radio for what's stored. A date (inherit: true) stores nil to follow
  # its production and 0 for all ages; a production stores nil for all ages.
  def self.choice_for(age, inherit: false)
    return INHERIT if inherit && age.nil?
    return ALL_AGES if age.to_i.zero?

    PRESETS.include?(age) ? age.to_s : OTHER
  end

  # The radio and the typed age, back to what's stored, or :invalid when
  # "Another age" isn't a whole number from 1 to 99.
  def self.value_for(choice, other, inherit: false)
    case choice.to_s
    when INHERIT then inherit ? nil : :invalid
    when ALL_AGES then inherit ? 0 : nil
    when OTHER
      typed = other.to_s.strip
      typed.match?(/\A\d{1,2}\z/) && AGES.cover?(typed.to_i) ? typed.to_i : :invalid
    else
      PRESETS.map(&:to_s).include?(choice.to_s) ? choice.to_i : :invalid
    end
  end

  # [value, title, hint] for the radio cards. A date's first card follows its
  # production, saying what that is.
  def self.choices(inherit: false, inherited_age: nil)
    [
      ([ INHERIT, "Same as the production", words(inherited_age) || "All ages" ] if inherit),
      [ ALL_AGES, "All ages", nil ],
      *PRESETS.map { |age| [ age.to_s, label(age), nil ] },
      [ OTHER, "Another age", nil ]
    ].compact
  end
end
