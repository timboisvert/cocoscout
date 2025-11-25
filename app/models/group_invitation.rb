class GroupInvitation < ApplicationRecord
  belongs_to :group
  belongs_to :invited_by, class_name: "Person", foreign_key: "invited_by_person_id", optional: true

  enum :permission_level, { owner: 0, write: 1, view: 2 }

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true
  validates :token, presence: true, uniqueness: true
  validates :permission_level, presence: true

  before_validation :generate_token, on: :create
  before_validation :normalize_email

  scope :pending, -> { where(accepted_at: nil) }
  scope :accepted, -> { where.not(accepted_at: nil) }

  def accepted?
    accepted_at.present?
  end

  def pending?
    accepted_at.nil?
  end

  private

  def generate_token
    self.token ||= SecureRandom.hex(20)
  end

  def normalize_email
    self.email = email.downcase.strip if email.present?
  end
end
