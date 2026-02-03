class AddChannelToEmailTemplates < ActiveRecord::Migration[8.1]
  def change
    # Channel determines how the template is delivered:
    # - email: Email only (auth, invitations to non-users)
    # - message: In-app message only
    # - both: Create message AND send email notification
    add_column :email_templates, :channel, :string, default: "email", null: false

    # Set channel based on template category/usage
    reversible do |dir|
      dir.up do
        # Audition cycle notifications → message (Phase 1)
        execute <<~SQL
          UPDATE email_templates
          SET channel = 'message'
          WHERE key IN (
            'audition_invitation',
            'audition_added_to_cast',
            'audition_not_cast',
            'audition_not_invited',
            'audition_request_notification',
            'talent_left_production'
          )
        SQL

        # Cast/show notifications → message (Phase 2)
        execute <<~SQL
          UPDATE email_templates
          SET channel = 'message'
          WHERE key IN (
            'cast_notification',
            'removed_from_cast_notification',
            'show_canceled'
          )
        SQL

        # Sign-up flow → both (Phase 3)
        execute <<~SQL
          UPDATE email_templates
          SET channel = 'both'
          WHERE key IN (
            'sign_up_confirmation',
            'sign_up_queued',
            'sign_up_slot_assigned',
            'sign_up_slot_changed',
            'sign_up_cancelled',
            'sign_up_registration_notification'
          )
        SQL

        # Reminders → message (Phase 4)
        execute <<~SQL
          UPDATE email_templates
          SET channel = 'message'
          WHERE key IN (
            'questionnaire_invitation',
            'payment_setup_reminder'
          )
        SQL

        # Everything else stays as 'email' (default)
        # - auth_signup, auth_password_reset, user_account_created
        # - person_invitation, team_invitation, group_invitation
        # - shoutout_invitation, shoutout_received
        # - vacancy_invitation, vacancy_invitation_linked
        # - unread_digest (meta-notification about messages)
        # - casting_table_notification (team-facing)
      end
    end
  end
end
