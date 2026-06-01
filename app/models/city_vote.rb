# frozen_string_literal: true

# A vote from a visitor (signed-in or by email) for a city they want the
# finder in next.
class CityVote < ApplicationRecord
  belongs_to :user, optional: true

  validates :city, :state, presence: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validate :voter_present

  before_validation :normalize_state

  # Returns top-N cities by raw vote count.
  def self.tallies(limit: 10)
    select("city, state, COUNT(*) AS n")
      .group(:city, :state)
      .order(Arel.sql("n DESC"))
      .limit(limit)
      .map { |row| [ [ row.city, row.state ], row.n.to_i ] }
  end

  private

  def normalize_state
    self.state = state.to_s.strip.upcase
    self.city  = city.to_s.strip
  end

  def voter_present
    return if user_id.present? || email.present?
    errors.add(:base, "Sign in or provide an email")
  end
end
