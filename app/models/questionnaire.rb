# frozen_string_literal: true

class Questionnaire < ApplicationRecord
  belongs_to :production, optional: true
  belongs_to :organization
  has_many :questions, as: :questionable, dependent: :destroy
  has_many :questionnaire_invitations, dependent: :destroy
  has_many :invited_people, lambda {
    where(questionnaire_invitations: { invitee_type: "Person" })
  }, through: :questionnaire_invitations, source: :invitee, source_type: "Person"
  has_many :questionnaire_responses, dependent: :destroy
  has_many :course_offerings

  has_rich_text :instruction_text

  validates :title, presence: true
  validates :token, presence: true, uniqueness: true

  before_validation :generate_token, on: :create

  scope :active, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }

  def respond_url
    if Rails.env.development?
      "http://localhost:3000/my/questionnaires/#{token}/form"
    else
      "https://www.cocoscout.com/my/questionnaires/#{token}/form"
    end
  end

  private

  def generate_token
    self.token = SecureRandom.alphanumeric(6).upcase if token.blank?
  end
end
