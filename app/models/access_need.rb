# frozen_string_literal: true

# A performer's or crew member's private access need (accessibility plan §3),
# for an audition (audition_cycle set) or for a production. Only the
# production team managers see it; it's never shown to other cast, never in
# exports, and PurgeAccessRequestsJob deletes it when the audition cycle or
# the production ends.
class AccessNeed < ApplicationRecord
  MAX_NOTE = 500

  belongs_to :person
  belongs_to :production
  belongs_to :audition_cycle, optional: true

  normalizes :note, with: ->(note) { note.to_s.strip.first(MAX_NOTE) }
  validates :note, presence: true

  scope :for_auditions, -> { where.not(audition_cycle_id: nil) }
  scope :for_productions, -> { where(audition_cycle_id: nil) }

  # Saves the box as the person left it: ticked with a note keeps (or
  # changes) the note; unticked, or ticked with nothing written, removes it.
  def self.record!(person:, production:, needed:, note:, audition_cycle: nil)
    existing = find_by(person: person, production: production, audition_cycle: audition_cycle)
    if needed && note.to_s.strip.present?
      (existing || new(person: person, production: production, audition_cycle: audition_cycle)).update!(note: note)
    else
      existing&.destroy!
      nil
    end
  end

  # An audition's need ends with its cycle: no longer active, or closed with
  # no audition still to come.
  def self.cycle_over?(cycle)
    return true unless cycle.active?

    closed = cycle.closes_at.present? && cycle.closes_at < Time.current
    closed && !cycle.audition_sessions.where(start_at: Time.current..).exists?
  end

  # A production's need ends with the production: no date still to come.
  def self.production_over?(production)
    !production.shows.where(canceled: false).where(date_and_time: Time.current.beginning_of_day..).exists?
  end
end
