class RoleVacancyInvitation < ApplicationRecord
  belongs_to :role_vacancy
  belongs_to :person

  before_create :generate_token
  before_create :set_invited_at

  scope :pending, -> { where(claimed_at: nil, declined_at: nil) }
  scope :claimed, -> { where.not(claimed_at: nil) }
  scope :declined, -> { where.not(declined_at: nil) }
  scope :unresolved, -> { joins(:role_vacancy).where(claimed_at: nil).merge(RoleVacancy.open) }

  validates :token, uniqueness: true, allow_nil: true

  delegate :role, :show, to: :role_vacancy

  def claimed?
    claimed_at.present?
  end

  def declined?
    declined_at.present?
  end

  def pending?
    claimed_at.nil? && declined_at.nil?
  end

  def claim!
    return false if claimed?
    return false unless role_vacancy.open?

    transaction do
      update!(claimed_at: Time.current)
      role_vacancy.fill!(person)
    end

    true
  end

  def decline!
    return false if claimed?
    return false if declined?

    update!(declined_at: Time.current)
    true
  end

  def expired?
    !role_vacancy.open?
  end

  # Can still claim if declined but vacancy is still open
  def can_claim?
    !claimed? && role_vacancy.open?
  end

  private

  def generate_token
    self.token = SecureRandom.urlsafe_base64(32)
  end

  def set_invited_at
    self.invited_at ||= Time.current
  end
end
