class Questionnaire < ApplicationRecord
  belongs_to :production
  has_many :questions, as: :questionable, dependent: :destroy
  has_many :questionnaire_invitations, dependent: :destroy
  has_many :invited_people, through: :questionnaire_invitations, source: :person
  has_many :questionnaire_responses, dependent: :destroy

  has_rich_text :instruction_text

  validates :title, presence: true
  validates :token, presence: true, uniqueness: true

  before_validation :generate_token, on: :create

  def respond_url
    if Rails.env.development?
      "http://localhost:3000/q/#{self.token}"
    else
      "https://www.cocoscout.com/q/#{self.token}"
    end
  end

  private

  def generate_token
    self.token = SecureRandom.alphanumeric(6).upcase if self.token.blank?
  end
end
