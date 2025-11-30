class PersonInvitation < ApplicationRecord
  belongs_to :organization, optional: true

  validates :email, presence: true
  validates :token, presence: true, uniqueness: true

  before_validation :generate_token, on: :create

  def generate_token
    self.token ||= SecureRandom.hex(20)
  end
end
