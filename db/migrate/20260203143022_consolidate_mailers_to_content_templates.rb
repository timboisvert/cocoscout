class ConsolidateMailersToContentTemplates < ActiveRecord::Migration[8.1]
  def up
    # ============================================
    # EMAIL-ONLY TEMPLATES (for accounts/auth)
    # ============================================

    # Auth - Welcome email
    ContentTemplate.find_or_create_by!(key: "auth_welcome") do |t|
      t.name = "Welcome Email"
      t.description = "Sent when a new user creates an account"
      t.category = "auth"
      t.channel = "email"
      t.subject = "Welcome to CocoScout"
      t.body = <<~HTML
        <p>Hi there!</p>
        <p>Welcome to CocoScout! Your account has been created successfully.</p>
        <p>You can now sign in and start exploring.</p>
      HTML
      t.available_variables = %w[user_email]
    end

    # Auth - Password reset
    ContentTemplate.find_or_create_by!(key: "auth_password_reset") do |t|
      t.name = "Password Reset Email"
      t.description = "Sent when a user requests a password reset"
      t.category = "auth"
      t.channel = "email"
      t.subject = "Reset your CocoScout password"
      t.body = <<~HTML
        <p>Hi there,</p>
        <p>We received a request to reset your password. Click the button below to choose a new password:</p>
        <p><a href="{{reset_url}}" style="display: inline-block; background-color: #ec4899; color: white; padding: 12px 24px; border-radius: 6px; text-decoration: none; font-weight: 500;">Reset Password</a></p>
        <p>If you didn't request this, you can safely ignore this email.</p>
        <p>This link will expire in 4 hours.</p>
      HTML
      t.available_variables = %w[reset_url]
    end

    # Person invitation (join CocoScout)
    ContentTemplate.find_or_create_by!(key: "person_invitation") do |t|
      t.name = "Person Invitation"
      t.description = "Sent when inviting someone to join CocoScout"
      t.category = "invitations"
      t.channel = "email"
      t.subject = "You've been invited to join {{organization_name}} on CocoScout"
      t.body = <<~HTML
        <p>Hi there!</p>
        <p>You've been invited to join <strong>{{organization_name}}</strong> on CocoScout.</p>
        {{#custom_message}}
        <p>{{custom_message}}</p>
        {{/custom_message}}
        <p><a href="{{accept_url}}" style="display: inline-block; background-color: #ec4899; color: white; padding: 12px 24px; border-radius: 6px; text-decoration: none; font-weight: 500;">Accept Invitation</a></p>
      HTML
      t.available_variables = %w[organization_name accept_url custom_message]
    end

    # Group invitation
    ContentTemplate.find_or_create_by!(key: "group_invitation") do |t|
      t.name = "Group Invitation"
      t.description = "Sent when inviting someone to join a group"
      t.category = "invitations"
      t.channel = "email"
      t.subject = "You've been invited to join {{group_name}} on CocoScout"
      t.body = <<~HTML
        <p>Hi there!</p>
        <p><strong>{{invited_by_name}}</strong> has invited you to join the group <strong>{{group_name}}</strong> on CocoScout.</p>
        {{#custom_message}}
        <p>{{custom_message}}</p>
        {{/custom_message}}
        <p><a href="{{accept_url}}" style="display: inline-block; background-color: #ec4899; color: white; padding: 12px 24px; border-radius: 6px; text-decoration: none; font-weight: 500;">Accept Invitation</a></p>
      HTML
      t.available_variables = %w[group_name invited_by_name accept_url custom_message]
    end

    # Shoutout notification
    ContentTemplate.find_or_create_by!(key: "shoutout_notification") do |t|
      t.name = "Shoutout Notification"
      t.description = "Sent when someone receives a shoutout"
      t.category = "notifications"
      t.channel = "email"
      t.subject = "{{author_name}} gave you a shoutout on CocoScout!"
      t.body = <<~HTML
        <p>Hey {{recipient_name}}!</p>
        <p><strong>{{author_name}}</strong> just gave you a shoutout:</p>
        <blockquote style="border-left: 4px solid #ec4899; padding-left: 16px; margin: 16px 0; font-style: italic;">
          {{shoutout_message}}
        </blockquote>
        <p><a href="{{shoutout_url}}" style="display: inline-block; background-color: #ec4899; color: white; padding: 12px 24px; border-radius: 6px; text-decoration: none; font-weight: 500;">View Shoutout</a></p>
      HTML
      t.available_variables = %w[author_name recipient_name shoutout_message shoutout_url]
    end

    # Team organization invitation
    ContentTemplate.find_or_create_by!(key: "team_organization_invitation") do |t|
      t.name = "Team Organization Invitation"
      t.description = "Sent when inviting someone to join an organization team"
      t.category = "invitations"
      t.channel = "email"
      t.subject = "You've been invited to join {{organization_name}}'s team on CocoScout"
      t.body = <<~HTML
        <p>Hi there!</p>
        <p>You've been invited to join <strong>{{organization_name}}</strong>'s team on CocoScout.</p>
        {{#custom_message}}
        <p>{{custom_message}}</p>
        {{/custom_message}}
        <p><a href="{{accept_url}}" style="display: inline-block; background-color: #ec4899; color: white; padding: 12px 24px; border-radius: 6px; text-decoration: none; font-weight: 500;">Accept Invitation</a></p>
      HTML
      t.available_variables = %w[organization_name accept_url custom_message]
    end

    # Team production invitation
    ContentTemplate.find_or_create_by!(key: "team_production_invitation") do |t|
      t.name = "Team Production Invitation"
      t.description = "Sent when inviting someone to join a production team"
      t.category = "invitations"
      t.channel = "email"
      t.subject = "You've been invited to join the {{production_name}} team on CocoScout"
      t.body = <<~HTML
        <p>Hi there!</p>
        <p>You've been invited to join the <strong>{{production_name}}</strong> team on CocoScout.</p>
        {{#custom_message}}
        <p>{{custom_message}}</p>
        {{/custom_message}}
        <p><a href="{{accept_url}}" style="display: inline-block; background-color: #ec4899; color: white; padding: 12px 24px; border-radius: 6px; text-decoration: none; font-weight: 500;">Accept Invitation</a></p>
      HTML
      t.available_variables = %w[production_name accept_url custom_message]
    end

    # Vacancy invitation - EMAIL + MESSAGE (both)
    ContentTemplate.find_or_create_by!(key: "vacancy_invitation") do |t|
      t.name = "Vacancy Invitation"
      t.description = "Sent when inviting someone to fill a role vacancy"
      t.category = "vacancies"
      t.channel = "both"
      t.subject = "You're invited to fill a role in {{production_name}}"
      t.body = <<~HTML
        <p>Hi {{recipient_name}},</p>
        <p>You've been invited to fill the <strong>{{role_name}}</strong> role for <strong>{{show_name}}</strong> on {{show_date}}.</p>
        {{#custom_message}}
        <p>{{custom_message}}</p>
        {{/custom_message}}
        <p><a href="{{claim_url}}" style="display: inline-block; background-color: #ec4899; color: white; padding: 12px 24px; border-radius: 6px; text-decoration: none; font-weight: 500;">View & Respond</a></p>
      HTML
      t.available_variables = %w[recipient_name production_name role_name show_name show_date claim_url custom_message]
    end

    # ============================================
    # MESSAGE-ONLY TEMPLATES (converting from email)
    # ============================================

    # Group - Added to group (was email, now message)
    ContentTemplate.find_or_create_by!(key: "group_member_added") do |t|
      t.name = "Added to Group"
      t.description = "Sent when someone is added to a group"
      t.category = "groups"
      t.channel = "message"
      t.subject = "You've been added to {{group_name}}"
      t.body = <<~HTML
        <p>Hi {{recipient_name}},</p>
        <p><strong>{{added_by_name}}</strong> has added you to the group <strong>{{group_name}}</strong>.</p>
        {{#custom_message}}
        <p>{{custom_message}}</p>
        {{/custom_message}}
      HTML
      t.available_variables = %w[recipient_name group_name added_by_name custom_message]
    end

    # Audition request submitted (producer notification) - now message only
    ContentTemplate.find_or_create_by!(key: "audition_request_submitted") do |t|
      t.name = "Audition Request Submitted"
      t.description = "Sent to producers when someone submits an audition request"
      t.category = "auditions"
      t.channel = "message"
      t.subject = "New audition request from {{requestable_name}}"
      t.body = <<~HTML
        <p>{{requestable_name}} has submitted an audition request for <strong>{{production_name}}</strong>.</p>
        <p><a href="{{review_url}}">Review the request</a></p>
      HTML
      t.available_variables = %w[requestable_name production_name review_url]
    end

    # Talent left production (producer notification) - now message only
    ContentTemplate.find_or_create_by!(key: "talent_left_production") do |t|
      t.name = "Talent Left Production"
      t.description = "Sent to producers when talent leaves a production"
      t.category = "auditions"
      t.channel = "message"
      t.subject = "{{person_name}} has left {{production_name}}'s talent pool"
      t.body = <<~HTML
        <p><strong>{{person_name}}</strong> has left the talent pool for <strong>{{production_name}}</strong>.</p>
        {{#groups_list}}
        <p>They were a member of: {{groups_list}}</p>
        {{/groups_list}}
      HTML
      t.available_variables = %w[person_name production_name groups_list]
    end

    # Questionnaire invitation - now message only
    ContentTemplate.find_or_create_by!(key: "questionnaire_invitation") do |t|
      t.name = "Questionnaire Invitation"
      t.description = "Sent when inviting someone to fill out a questionnaire"
      t.category = "questionnaires"
      t.channel = "message"
      t.subject = "{{production_name}}: Please complete this questionnaire"
      t.body = <<~HTML
        <p>Hi {{recipient_name}},</p>
        <p>You've been invited to complete a questionnaire for <strong>{{production_name}}</strong>.</p>
        {{#custom_message}}
        <p>{{custom_message}}</p>
        {{/custom_message}}
        <p><a href="{{questionnaire_url}}">Complete Questionnaire</a></p>
      HTML
      t.available_variables = %w[recipient_name production_name questionnaire_url custom_message]
    end

    # Payment setup reminder - now message only
    ContentTemplate.find_or_create_by!(key: "payment_setup_reminder") do |t|
      t.name = "Payment Setup Reminder"
      t.description = "Reminder to set up payment information"
      t.category = "payments"
      t.channel = "message"
      t.subject = "Please set up your payment information"
      t.body = <<~HTML
        <p>Hi {{recipient_name}},</p>
        <p>Please set up your payment information for <strong>{{production_name}}</strong> so we can pay you.</p>
        {{#custom_message}}
        <p>{{custom_message}}</p>
        {{/custom_message}}
        <p><a href="{{setup_url}}">Set Up Payment</a></p>
      HTML
      t.available_variables = %w[recipient_name production_name setup_url custom_message]
    end

    # Casting table notification - now message only
    ContentTemplate.find_or_create_by!(key: "casting_table_notification") do |t|
      t.name = "Casting Table Notification"
      t.description = "Notifies talent of casting table assignments"
      t.category = "casting"
      t.channel = "message"
      # Keep existing template if it exists, just update channel
    end
    ContentTemplate.where(key: "casting_table_notification").update_all(channel: "message")

    # Update existing audition templates to message-only
    %w[
      audition_invitation
      audition_added_to_cast
      audition_not_cast
      audition_not_invited
    ].each do |key|
      ContentTemplate.where(key: key).update_all(channel: "message")
    end

    # Update existing casting templates to message-only
    %w[
      cast_notification
      removed_from_cast_notification
    ].each do |key|
      ContentTemplate.where(key: key).update_all(channel: "message")
    end
  end

  def down
    # Remove the new templates
    %w[
      auth_welcome
      auth_password_reset
      person_invitation
      group_invitation
      shoutout_notification
      team_organization_invitation
      team_production_invitation
      vacancy_invitation
      group_member_added
      audition_request_submitted
      talent_left_production
    ].each do |key|
      ContentTemplate.find_by(key: key)&.destroy
    end

    # Revert channels back to email/both
    %w[
      audition_invitation
      audition_added_to_cast
      audition_not_cast
      audition_not_invited
      questionnaire_invitation
      payment_setup_reminder
      casting_table_notification
      cast_notification
      removed_from_cast_notification
    ].each do |key|
      ContentTemplate.where(key: key).update_all(channel: "email")
    end
  end
end
