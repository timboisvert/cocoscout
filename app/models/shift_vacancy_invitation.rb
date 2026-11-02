# frozen_string_literal: true

# One person asked to cover a shift (RoleVacancyInvitation's shape): a token
# for the claim page, when they were asked, whether they claimed or declined,
# and the words the manager sent them.
class ShiftVacancyInvitation < ApplicationRecord
  belongs_to :shift_vacancy
  belongs_to :person

  before_create :generate_token
  before_create :set_invited_at

  scope :pending, -> { where(claimed_at: nil, declined_at: nil) }
  scope :claimed, -> { where.not(claimed_at: nil) }
  scope :declined, -> { where.not(declined_at: nil) }
  # Still worth showing the invitee: not claimed, and the vacancy still active.
  scope :unresolved, -> { joins(:shift_vacancy).where(claimed_at: nil).merge(ShiftVacancy.active) }

  validates :token, uniqueness: true, allow_nil: true

  delegate :shift, to: :shift_vacancy

  def claimed?
    claimed_at.present?
  end

  def declined?
    declined_at.present?
  end

  def pending?
    claimed_at.nil? && declined_at.nil?
  end

  # First to claim gets it: the vacancy's row lock lines two claims up, and
  # the second finds it filled.
  def claim!
    claimed = false
    shift_vacancy.with_lock do
      if can_claim?
        update!(claimed_at: Time.current)
        claimed = shift_vacancy.fill!(person, accepted: true)
      end
    end
    claimed
  end

  def decline!
    return false if claimed? || declined?

    update!(declined_at: Time.current)
    true
  end

  def expired?
    !shift_vacancy.active?
  end

  # Declined but still open: they can change their mind. Already on the shift
  # (a manager put them on meanwhile): nothing to claim.
  def can_claim?
    !claimed? && shift_vacancy.active? && !shift.shift_assignments.active.exists?(person_id: person_id)
  end

  private

  def generate_token
    self.token = SecureRandom.urlsafe_base64(32)
  end

  def set_invited_at
    self.invited_at ||= Time.current
  end
end
