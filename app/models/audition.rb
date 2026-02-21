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

  # Acceptance status helpers
  def accepted?
    accepted_at.present?
  end

  def declined?
    declined_at.present?
  end

  def pending_response?
    accepted_at.nil? && declined_at.nil?
  end

  def response_status
    if accepted?
      :accepted
    elsif declined?
      :declined
    else
      :pending
    end
  end

  def accept!
    update!(accepted_at: Time.current, declined_at: nil)
  end

  def decline!
    update!(declined_at: Time.current, accepted_at: nil)
  end
end
