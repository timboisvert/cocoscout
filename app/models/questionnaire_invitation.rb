class QuestionnaireInvitation < ApplicationRecord
  belongs_to :questionnaire
  belongs_to :invitee, polymorphic: true

  validates :questionnaire, presence: true
  validates :invitee, presence: true
  validates :invitee_id, uniqueness: { scope: [ :questionnaire_id, :invitee_type ] }
end
