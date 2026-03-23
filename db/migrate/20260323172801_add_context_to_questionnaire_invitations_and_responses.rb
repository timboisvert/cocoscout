class AddContextToQuestionnaireInvitationsAndResponses < ActiveRecord::Migration[8.1]
  def change
    # Add polymorphic context to invitations
    add_column :questionnaire_invitations, :context_type, :string
    add_column :questionnaire_invitations, :context_id, :bigint
    add_index :questionnaire_invitations, [ :context_type, :context_id ]

    # Add polymorphic context to responses
    add_column :questionnaire_responses, :context_type, :string
    add_column :questionnaire_responses, :context_id, :bigint
    add_index :questionnaire_responses, [ :context_type, :context_id ]

    # Replace old uniqueness constraints with context-aware ones
    remove_index :questionnaire_invitations, name: "index_questionnaire_invitations_unique"
    add_index :questionnaire_invitations,
              [ :invitee_type, :invitee_id, :questionnaire_id, :context_type, :context_id ],
              unique: true,
              name: "index_q_invitations_unique_with_context"

    remove_index :questionnaire_responses, name: "index_questionnaire_responses_unique"
    add_index :questionnaire_responses,
              [ :respondent_type, :respondent_id, :questionnaire_id, :context_type, :context_id ],
              unique: true,
              name: "index_q_responses_unique_with_context"
  end
end
