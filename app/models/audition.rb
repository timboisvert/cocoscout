# frozen_string_literal: true

class Audition < ApplicationRecord
  belongs_to :auditionable, polymorphic: true
  belongs_to :audition_request
  belongs_to :audition_session
  has_many :audition_votes, dependent: :destroy

  # Alias for backward compatibility
  def person
    auditionable if auditionable_type == "Person"
  end

  # Vote helper methods
  def vote_for(user)
    audition_votes.find_by(user: user)
  end

  def vote_counts
    @vote_counts ||= {
      yes: audition_votes.yes.count,
      no: audition_votes.no.count,
      maybe: audition_votes.maybe.count
    }
  end

  def votes_with_comments
    audition_votes.includes(user: :default_person).where.not(comment: [ nil, "" ]).order(created_at: :desc)
  end
end
