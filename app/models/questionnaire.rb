class Questionnaire < ApplicationRecord
  belongs_to :production
  has_many :questions, as: :questionable, dependent: :destroy
  has_many :questionnaire_invitations, dependent: :destroy
  has_many :invited_people, -> { where(questionnaire_invitations: { invitee_type: "Person" }) }, through: :questionnaire_invitations, source: :invitee, source_type: "Person"
  has_many :questionnaire_responses, dependent: :destroy

  has_rich_text :instruction_text

  serialize :availability_show_ids, type: Array, coder: YAML

  validates :title, presence: true
  validates :token, presence: true, uniqueness: true

  before_validation :generate_token, on: :create

  scope :active, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }

  # Cached response statistics for display
  def cached_response_stats
    Rails.cache.fetch(["questionnaire_stats_v1", id, questionnaire_responses.maximum(:updated_at), questionnaire_invitations.maximum(:updated_at)], expires_in: 5.minutes) do
      total_invited = questionnaire_invitations.count
      total_responded = questionnaire_responses.count
      {
        invited: total_invited,
        responded: total_responded,
        response_rate: total_invited > 0 ? (total_responded.to_f / total_invited * 100).round(1) : 0
      }
    end
  end

  def respond_url
    if Rails.env.development?
      "http://localhost:3000/my/questionnaires/#{self.token}/form"
    else
      "https://www.cocoscout.com/my/questionnaires/#{self.token}/form"
    end
  end

  private

  def generate_token
    self.token = SecureRandom.alphanumeric(6).upcase if self.token.blank?
  end
end
