# frozen_string_literal: true

class ReorganizeContentTemplateCategories < ActiveRecord::Migration[8.0]
  def up
    # Reorganize categories from invitation/notification/reminder/confirmation/marketing/system
    # to auth/profiles/casting/signups/shows/payments/messages

    # Auth templates (formerly system)
    execute <<~SQL
      UPDATE content_templates SET category = 'auth'
      WHERE key IN ('auth_signup', 'auth_password_reset', 'user_account_created')
    SQL

    # Profiles templates (groups, shoutouts, invitations)
    execute <<~SQL
      UPDATE content_templates SET category = 'profiles'
      WHERE key IN ('group_invitation', 'shoutout_invitation', 'shoutout_received', 'person_invitation', 'team_invitation')
    SQL

    # Casting templates (cast decisions and notifications)
    execute <<~SQL
      UPDATE content_templates SET category = 'casting'
      WHERE key IN ('audition_added_to_cast', 'audition_not_cast', 'cast_notification', 'removed_from_cast_notification', 'casting_table_notification')
    SQL

    # Sign-ups templates (audition invitations/requests AND sign-up forms)
    execute <<~SQL
      UPDATE content_templates SET category = 'signups'
      WHERE key IN (
        'audition_invitation', 'audition_not_invited', 'audition_request_notification', 'questionnaire_invitation',
        'sign_up_confirmation', 'sign_up_queued', 'sign_up_slot_assigned', 'sign_up_slot_changed',
        'sign_up_cancelled', 'sign_up_registration_notification'
      )
    SQL

    # Shows templates (show cancellations, vacancies)
    execute <<~SQL
      UPDATE content_templates SET category = 'shows'
      WHERE key IN ('show_canceled', 'vacancy_invitation', 'vacancy_invitation_linked', 'talent_left_production')
    SQL

    # Payments templates
    execute <<~SQL
      UPDATE content_templates SET category = 'payments'
      WHERE key IN ('payment_setup_reminder')
    SQL

    # Messages templates
    execute <<~SQL
      UPDATE content_templates SET category = 'messages'
      WHERE key IN ('unread_digest', 'talent_pool_message')
    SQL
  end

  def down
    # Restore original categories
    execute <<~SQL
      UPDATE content_templates SET category = 'system'
      WHERE key IN ('auth_signup', 'auth_password_reset', 'user_account_created')
    SQL

    execute <<~SQL
      UPDATE content_templates SET category = 'invitation'
      WHERE key IN ('group_invitation', 'shoutout_invitation', 'person_invitation', 'team_invitation',
                    'audition_invitation', 'vacancy_invitation', 'vacancy_invitation_linked')
    SQL

    execute <<~SQL
      UPDATE content_templates SET category = 'notification'
      WHERE key IN ('shoutout_received', 'audition_added_to_cast', 'audition_not_cast',
                    'audition_not_invited', 'audition_request_notification', 'cast_notification',
                    'removed_from_cast_notification', 'casting_table_notification',
                    'show_canceled', 'talent_left_production', 'unread_digest',
                    'sign_up_slot_assigned', 'sign_up_slot_changed', 'sign_up_cancelled',
                    'sign_up_registration_notification', 'talent_pool_message')
    SQL

    execute <<~SQL
      UPDATE content_templates SET category = 'reminder'
      WHERE key IN ('payment_setup_reminder', 'questionnaire_invitation')
    SQL

    execute <<~SQL
      UPDATE content_templates SET category = 'confirmation'
      WHERE key IN ('sign_up_confirmation', 'sign_up_queued')
    SQL
  end
end
