# frozen_string_literal: true

# Seeds for EmailTemplate records
# Run with: rails db:seed:email_templates
# Or: EmailTemplate.destroy_all && load(Rails.root.join("db/seeds/email_templates.rb"))
#
# IMPORTANT: This file contains the ACTUAL email content that was previously
# hardcoded in controllers and views. When updating these templates, update
# both this seed file AND the corresponding controller/view code to use
# EmailTemplateService.render() with the same template key.

module EmailTemplateSeeds
  class << self
    def seed!
      Rails.logger.info "Seeding email templates..."

      templates = [
        # ============================================
        # TALENT POOL MESSAGE
        # For My::MessagesController#send_message
        # ============================================
        {
          key: "talent_pool_message",
          name: "Talent Pool Message",
          category: "notification",
          subject: "{{subject}}",
          description: "Message sent from a user to a production's team via the talent pool. Subject and body are passed through as provided by the sender.",
          template_type: "passthrough",
          mailer_class: "My::TalentMessageMailer",
          mailer_action: "send_to_production",
          prepend_production_name: true,
          body: "{{body_html}}",
          available_variables: [
            { name: "sender_name", description: "Name of the sender (person)" },
            { name: "sender_email", description: "Email address of the sender" },
            { name: "production_name", description: "Name of the production" },
            { name: "body_html", description: "HTML content of the message" },
            { name: "subject", description: "Subject of the message" }
          ]
        },
        # ============================================
        # AUTH EMAILS
        # ============================================
        {
          key: "auth_signup",
          name: "Welcome Email",
          category: "system",
          subject: "Welcome to CocoScout",
          description: "Sent when a user creates a new account. Welcomes them and provides a link to sign in.",
          template_type: "structured",
          mailer_class: "AuthMailer",
          mailer_action: "signup",
          body: <<~HTML,
            <p>Welcome to CocoScout!</p>
            <p>Your account has been created successfully.</p>
            <p>You can sign in at any time using your email address: {{user_email}}</p>
            <p><a href="{{signin_url}}">Sign in to CocoScout</a></p>
          HTML
          available_variables: [
            { name: "user_email", description: "The user's email address" },
            { name: "signin_url", description: "URL to the sign in page" }
          ]
        },
        {
          key: "auth_password_reset",
          name: "Password Reset",
          category: "system",
          subject: "Reset your CocoScout password",
          description: "Sent when a user requests a password reset. Contains a secure link to reset their password.",
          template_type: "structured",
          mailer_class: "AuthMailer",
          mailer_action: "password",
          body: <<~HTML,
            <p>Hello,</p>
            <p>We received a request to reset your CocoScout password.</p>
            <p><a href="{{reset_url}}">Click here to reset your password</a></p>
            <p>If you didn't request this, you can safely ignore this email.</p>
            <p>This link will expire in 24 hours.</p>
          HTML
          available_variables: [
            { name: "reset_url", description: "Secure URL to reset the password" }
          ]
        },

        # ============================================
        # GROUP INVITATIONS
        # Source: group_invitations_controller.rb
        # ============================================
        {
          key: "group_invitation",
          name: "Group Invitation",
          category: "invitation",
          subject: "You've been invited to join {{group_name}} on CocoScout",
          description: "Invites someone to join a group/ensemble. Supports custom messages from the inviter.",
          template_type: "hybrid",
          mailer_class: "GroupInvitationMailer",
          mailer_action: "invitation",
          body: <<~HTML,
            <p>Hello,</p>
            <p>You've been invited to join {{group_name}} on CocoScout.</p>
            {{#custom_message}}
            <p>{{custom_message}}</p>
            {{/custom_message}}
            <p><a href="{{accept_url}}">Accept Invitation</a></p>
          HTML
          available_variables: [
            { name: "group_name", description: "Name of the group being invited to" },
            { name: "custom_message", description: "Optional custom message from the inviter" },
            { name: "accept_url", description: "URL to accept the invitation" }
          ]
        },

        # ============================================
        # SHOUTOUTS
        # Source: my/shoutouts_controller.rb
        # ============================================
        {
          key: "shoutout_invitation",
          name: "Shoutout New User Invitation",
          category: "invitation",
          subject: "{{author_name}} gave you a shoutout on CocoScout!",
          description: "Sent when someone gives a shoutout to a person not yet on CocoScout. Invites them to join.",
          template_type: "hybrid",
          mailer_class: "Manage::PersonMailer",
          mailer_action: "person_invitation",
          body: <<~HTML,
            <p>{{author_name}} gave you a shoutout on CocoScout!</p>
            <p>Join CocoScout to see your shoutout and connect with others in the industry.</p>
            <p><a href="{{setup_url}}">Create Your Account</a></p>
          HTML
          available_variables: [
            { name: "author_name", description: "Name of the person who gave the shoutout" },
            { name: "setup_url", description: "URL to set up their account" }
          ]
        },
        {
          key: "shoutout_received",
          name: "Shoutout Received",
          category: "notification",
          subject: "{{author_name}} gave you a shoutout on CocoScout!",
          description: "Notifies an existing user when someone gives them a shoutout. Content is hidden - they must log in to see it.",
          body: <<~HTML,
            <p>Hello {{recipient_name}},</p>
            <p><strong>{{author_name}}</strong> gave you a shoutout on CocoScout!</p>
            <p>Log in to see what they said about you.</p>
            <p><a href="{{shoutouts_url}}">View Your Shoutouts</a></p>
          HTML
          available_variables: [
            { name: "recipient_name", description: "Name of the person receiving the shoutout" },
            { name: "author_name", description: "Name of the person who gave the shoutout" },
            { name: "shoutouts_url", description: "URL to view received shoutouts" }
          ]
        },

        # ============================================
        # VACANCY INVITATIONS
        # Source: manage/vacancies/show.html.erb
        # ============================================
        {
          key: "vacancy_invitation",
          name: "Role Vacancy Invitation",
          category: "invitation",
          subject: "[{{production_name}}] Replacement needed for {{show_date}} {{event_name}}",
          description: "Invites someone to fill a vacant role in a show. The subject and body are editable before sending.",
          template_type: "hybrid",
          mailer_class: "VacancyInvitationMailer",
          mailer_action: "invitation_email",
          body: <<~HTML,
            <p>A replacement is needed for the {{role_name}} role in {{production_name}}.</p>
            <p>Show:</p>
            <p>{{show_info}}</p>
            <p>Role: {{role_name}}</p>
            <p>If you're available and interested, click the link below to claim this spot.</p>
            <p>Thank you,<br>{{production_name}}</p>
          HTML
          available_variables: [
            { name: "production_name", description: "Name of the production" },
            { name: "role_name", description: "Name of the role to fill" },
            { name: "event_name", description: "Event type (e.g., 'Performance', 'Rehearsal')" },
            { name: "show_date", description: "Date of the show (e.g., 'Jan 5')" },
            { name: "show_info", description: "Full show date/time info" },
            { name: "claim_url", description: "URL to claim the vacancy" }
          ]
        },
        {
          key: "vacancy_invitation_linked",
          name: "Role Vacancy Invitation (Linked Shows)",
          category: "invitation",
          subject: "[{{production_name}}] Replacement needed for {{show_count}} linked shows",
          description: "Invites someone to fill a vacant role across multiple linked shows.",
          template_type: "hybrid",
          mailer_class: "VacancyInvitationMailer",
          mailer_action: "invitation_email",
          body: <<~HTML,
            <p>A replacement is needed for the {{role_name}} role in {{production_name}}.</p>
            <p>Shows ({{show_count}} linked events):</p>
            <p>{{shows_list}}</p>
            <p>Role: {{role_name}}</p>
            <p>If you're available and interested, click the link below to claim this spot.</p>
            <p>Thank you,<br>{{production_name}}</p>
          HTML
          available_variables: [
            { name: "production_name", description: "Name of the production" },
            { name: "role_name", description: "Name of the role to fill" },
            { name: "show_count", description: "Number of linked shows" },
            { name: "shows_list", description: "List of all show dates/times" },
            { name: "claim_url", description: "URL to claim the vacancy" }
          ]
        },

        # ============================================
        # AUDITION EMAILS
        # Source: manage/auditions_controller.rb, _finalize_notify_form.html.erb
        # ============================================
        {
          key: "audition_added_to_cast",
          name: "Audition: Added to Cast",
          category: "notification",
          subject: "Audition Results for {{production_name}}",
          description: "Sent to auditionees who are being added to a cast/talent pool. From auditions_controller.rb#generate_default_cast_email",
          template_type: "hybrid",
          mailer_class: "Manage::AuditionMailer",
          mailer_action: "casting_notification",
          body: <<~HTML,
            <p>Dear {{recipient_name}},</p>
            <p>Congratulations! We're excited to let you know you've been added to {{production_name}}.</p>
            <p>Your audition impressed us, and we believe you'll be a great addition to the team. We look forward to working with you.</p>
            <p>Please confirm your acceptance by {{confirm_by_date}}.</p>
            <p>Best regards,<br>The {{production_name}} Team</p>
          HTML
          available_variables: [
            { name: "recipient_name", description: "Name of the auditionee" },
            { name: "production_name", description: "Name of the production" },
            { name: "confirm_by_date", description: "Optional date to confirm by" }
          ]
        },
        {
          key: "audition_not_cast",
          name: "Audition: Not Being Added",
          category: "notification",
          subject: "Audition Results for {{production_name}}",
          description: "Sent to auditionees who are not being added to a cast. From auditions_controller.rb#generate_default_rejection_email",
          template_type: "hybrid",
          mailer_class: "Manage::AuditionMailer",
          mailer_action: "casting_notification",
          body: <<~HTML,
            <p>Dear {{recipient_name}},</p>
            <p>Thank you so much for auditioning for {{production_name}}. We truly appreciate the time and effort you put into your audition.</p>
            <p>Unfortunately, we won't be able to offer you a role in this production at this time. We were impressed by your talent and encourage you to audition for future productions.</p>
            <p>We hope to work with you in the future.</p>
            <p>Best regards,<br>The {{production_name}} Team</p>
          HTML
          available_variables: [
            { name: "recipient_name", description: "Name of the auditionee" },
            { name: "production_name", description: "Name of the production" }
          ]
        },
        {
          key: "audition_invitation",
          name: "Audition Invitation",
          category: "invitation",
          subject: "{{production_name}} Auditions",
          description: "Invites talent to audition. From auditions_controller.rb#generate_default_invitation_email",
          template_type: "hybrid",
          mailer_class: "Manage::AuditionMailer",
          mailer_action: "invitation_notification",
          body: <<~HTML,
            <p>Dear {{recipient_name}},</p>
            <p>Congratulations! You've been invited to audition for {{production_name}}.</p>
            <p>Your audition schedule is now available. Please log in to view your audition time and location details.</p>
            <p>We look forward to seeing you!</p>
            <p>Best regards,<br>The {{production_name}} Team</p>
          HTML
          available_variables: [
            { name: "recipient_name", description: "Name of the person being invited" },
            { name: "production_name", description: "Name of the production" }
          ]
        },
        {
          key: "audition_not_invited",
          name: "Audition: Not Invited",
          category: "notification",
          subject: "{{production_name}} Auditions",
          description: "Sent to those not being invited to audition. From auditions_controller.rb#generate_default_not_invited_email",
          template_type: "hybrid",
          mailer_class: "Manage::AuditionMailer",
          mailer_action: "invitation_notification",
          body: <<~HTML,
            <p>Dear {{recipient_name}},</p>
            <p>Thank you so much for your interest in {{production_name}}. We truly appreciate you taking the time to apply.</p>
            <p>Unfortunately, we won't be able to offer you an audition for this production at this time. We received many qualified applicants and had to make some difficult decisions.</p>
            <p>We encourage you to apply for future productions and wish you all the best in your performing arts journey.</p>
            <p>Best regards,<br>The {{production_name}} Team</p>
          HTML
          available_variables: [
            { name: "recipient_name", description: "Name of the person" },
            { name: "production_name", description: "Name of the production" }
          ]
        },
        {
          key: "audition_request_notification",
          name: "Audition Request Received",
          category: "notification",
          subject: "[{{production_name}}] New audition request from {{requester_name}}",
          description: "Notifies producers when someone submits an audition request.",
          template_type: "structured",
          mailer_class: "Manage::AuditionMailer",
          mailer_action: "audition_request_notification",
          body: <<~HTML,
            <p>Hello {{recipient_name}},</p>
            <p>A new audition request has been submitted for {{production_name}}.</p>
            <p><strong>From:</strong> {{requester_name}}</p>
            <p><a href="{{request_url}}">View Request</a></p>
          HTML
          available_variables: [
            { name: "recipient_name", description: "Name of the producer receiving notification" },
            { name: "production_name", description: "Name of the production" },
            { name: "requester_name", description: "Name of the person/group requesting audition" },
            { name: "request_url", description: "URL to view the audition request" }
          ]
        },
        {
          key: "talent_left_production",
          name: "Talent Left Production",
          category: "notification",
          subject: "[{{production_name}}] {{talent_name}} has left the talent pool",
          description: "Notifies producers when a talent removes themselves from a production's talent pool.",
          template_type: "structured",
          mailer_class: "Manage::AuditionMailer",
          mailer_action: "talent_left_production",
          body: <<~HTML,
            <p>Hello {{recipient_name}},</p>
            <p>{{talent_name}} has left the {{production_name}} talent pool.</p>
            {{#groups_removed}}
            <p>The following groups were also removed: {{groups_removed}}</p>
            {{/groups_removed}}
            <p><a href="{{talent_pool_url}}">View Talent Pool</a></p>
          HTML
          available_variables: [
            { name: "recipient_name", description: "Name of the producer receiving notification" },
            { name: "production_name", description: "Name of the production" },
            { name: "talent_name", description: "Name of the person who left" },
            { name: "groups_removed", description: "Names of groups that were also removed" },
            { name: "talent_pool_url", description: "URL to view the talent pool" }
          ]
        },
        {
          key: "sign_up_registration_notification",
          name: "Sign-Up Registration Received",
          category: "notification",
          subject: "New sign-up from {{registrant_name}}",
          description: "Notifies production team when someone registers for a sign-up form.",
          template_type: "structured",
          mailer_class: "Manage::SignUpMailer",
          mailer_action: "registration_notification",
          prepend_production_name: true,
          body: <<~HTML,
            <p>Hello {{recipient_name}},</p>
            <p>A new registration has been submitted for <strong>{{sign_up_form_name}}</strong>.</p>
            <p><strong>From:</strong> {{registrant_name}}</p>
            <p><strong>Slot:</strong> {{slot_name}}</p>
            {{#event_info}}
            <p><strong>Event:</strong> {{event_info}}</p>
            {{/event_info}}
            <p><a href="{{registrations_url}}">View Registrations</a></p>
          HTML
          available_variables: [
            { name: "recipient_name", description: "Name of the producer receiving notification" },
            { name: "production_name", description: "Name of the production" },
            { name: "sign_up_form_name", description: "Name of the sign-up form" },
            { name: "registrant_name", description: "Name of the person who registered" },
            { name: "slot_name", description: "Name of the slot they registered for" },
            { name: "event_info", description: "Event date and time if applicable" },
            { name: "registrations_url", description: "URL to view registrations" }
          ]
        },

        # ============================================
        # AVAILABILITY REQUESTS
        # Source: manage/availability_controller.rb
        # ============================================
        {
          key: "availability_request",
          name: "Availability Request",
          category: "reminder",
          subject: "Please submit your availability for {{production_name}}",
          description: "Requests a person to submit their availability. From availability_controller.rb#generate_default_message",
          template_type: "hybrid",
          mailer_class: "Manage::AvailabilityMailer",
          mailer_action: "request_availability",
          body: <<~HTML,
            <p>Please submit your availability for the following upcoming {{production_name}} shows & events:</p>
            <p>{{shows_list}}</p>
            <p>You can update your availability by visiting:</p>
            <p><a href="{{availability_url}}">{{availability_url}}</a></p>
          HTML
          available_variables: [
            { name: "production_name", description: "Name of the production" },
            { name: "shows_list", description: "Bullet list of shows with dates and times" },
            { name: "availability_url", description: "URL to submit availability" }
          ]
        },
        {
          key: "availability_request_group",
          name: "Availability Request (Group)",
          category: "reminder",
          subject: "Please submit availability for {{group_name}} - {{production_name}}",
          description: "Requests a group to submit their collective availability.",
          template_type: "hybrid",
          mailer_class: "Manage::AvailabilityMailer",
          mailer_action: "request_availability_for_group",
          body: <<~HTML,
            <p>Please submit availability for {{group_name}} for the following upcoming {{production_name}} shows & events:</p>
            <p>{{shows_list}}</p>
            <p>You can update your availability by visiting:</p>
            <p><a href="{{availability_url}}">{{availability_url}}</a></p>
          HTML
          available_variables: [
            { name: "group_name", description: "Name of the group" },
            { name: "production_name", description: "Name of the production" },
            { name: "shows_list", description: "Bullet list of shows with dates and times" },
            { name: "availability_url", description: "URL to submit availability" }
          ]
        },

        # ============================================
        # CASTING EMAILS
        # Source: manage/casting_controller.rb
        # ============================================
        {
          key: "cast_notification",
          name: "Cast Notification",
          category: "notification",
          subject: "Cast Confirmation: {{production_name}} - {{show_dates}}",
          description: "Notifies someone they've been cast. From casting_controller.rb#default_cast_email_subject/body",
          template_type: "hybrid",
          mailer_class: "Manage::CastingMailer",
          mailer_action: "cast_notification",
          body: <<~HTML,
            <p>You have been cast for {{production_name}}:</p>
            <ul>
            {{shows_list}}
            </ul>
            <p>Please let us know if you have any scheduling conflicts or questions.</p>
          HTML
          available_variables: [
            { name: "production_name", description: "Name of the production" },
            { name: "show_dates", description: "Formatted date(s) for subject line" },
            { name: "shows_list", description: "HTML list items of show dates/times" }
          ]
        },
        {
          key: "removed_from_cast_notification",
          name: "Removed from Cast Notification",
          category: "notification",
          subject: "Casting Update - {{production_name}} - {{show_dates}}",
          description: "Notifies someone they've been removed from a cast. From casting_controller.rb#default_removed_email_subject/body",
          template_type: "hybrid",
          mailer_class: "Manage::CastingMailer",
          mailer_action: "removed_notification",
          body: <<~HTML,
            <p>There has been a change to the casting for {{production_name}}.</p>
            <p>You are no longer cast for:</p>
            <ul>
            {{shows_list}}
            </ul>
            <p>If you have any questions, please contact us.</p>
          HTML
          available_variables: [
            { name: "production_name", description: "Name of the production" },
            { name: "show_dates", description: "Formatted date(s) for subject line" },
            { name: "shows_list", description: "HTML list items of show dates/times" }
          ]
        },
        {
          key: "production_message",
          name: "Production Message",
          category: "notification",
          subject: "{{subject}}",
          description: "General-purpose email from production team to talent. Can be used for casting announcements, directory messages, or any production-related communication. Subject and body are fully customizable.",
          template_type: "passthrough",
          mailer_class: "Manage::ProductionMailer",
          mailer_action: "send_message",
          body: <<~HTML,
            {{body_content}}
          HTML
          available_variables: [
            { name: "subject", description: "Custom email subject" },
            { name: "body_content", description: "Custom HTML body content" }
          ]
        },

        # ============================================
        # PERSON INVITATIONS
        # Source: manage/people_controller.rb
        # ============================================
        {
          key: "person_invitation",
          name: "Person Invitation to CocoScout",
          category: "invitation",
          subject: "You've been invited to join {{organization_name}} on CocoScout",
          description: "Invites someone to join an organization. From people_controller.rb#default_invitation_subject/message",
          template_type: "hybrid",
          mailer_class: "Manage::PersonMailer",
          mailer_action: "person_invitation",
          body: <<~HTML,
            <p>Welcome to CocoScout!</p>
            <p>{{organization_name}} is using CocoScout to manage its productions, auditions, and casting.</p>
            <p>To get started, please click the link below to set a password and create your account.</p>
            <p><a href="{{setup_url}}">Set Up Your Account</a></p>
          HTML
          available_variables: [
            { name: "organization_name", description: "Name of the organization" },
            { name: "setup_url", description: "URL to set up the account/password" }
          ]
        },

        # ============================================
        # QUESTIONNAIRE INVITATIONS
        # Source: manage/questionnaires/show.html.erb
        # ============================================
        {
          key: "questionnaire_invitation",
          name: "Questionnaire Invitation",
          category: "reminder",
          subject: "{{production_name}} - {{questionnaire_title}}",
          description: "Invites talent to complete a questionnaire. From questionnaires/show.html.erb",
          template_type: "hybrid",
          mailer_class: "Manage::QuestionnaireMailer",
          mailer_action: "invitation",
          body: <<~HTML,
            <p>You're invited to respond to {{questionnaire_title}} for {{production_name}}.</p>
            <p>Please click the link below to access the questionnaire:</p>
            <p><a href="{{questionnaire_url}}">{{questionnaire_url}}</a></p>
            <p>Thank you!</p>
          HTML
          available_variables: [
            { name: "production_name", description: "Name of the production" },
            { name: "questionnaire_title", description: "Title of the questionnaire" },
            { name: "questionnaire_url", description: "URL to complete the questionnaire" }
          ]
        },

        # ============================================
        # TEAM INVITATIONS
        # Source: manage/team_controller.rb
        # ============================================
        {
          key: "team_invitation",
          name: "Team Invitation (Organization)",
          category: "invitation",
          subject: "You've been invited to join {{organization_name}}'s team on CocoScout",
          description: "Invites someone to join an organization's management team. From team_controller.rb",
          template_type: "hybrid",
          mailer_class: "Manage::TeamMailer",
          mailer_action: "invite",
          body: <<~HTML,
            <p>Welcome to CocoScout!</p>
            <p>{{organization_name}} is using CocoScout to manage its productions. You've been invited to join the team.</p>
            <p>Click the link below to accept the invitation and sign in or create an account.</p>
            <p><a href="{{accept_url}}">Accept Invitation</a></p>
          HTML
          available_variables: [
            { name: "organization_name", description: "Name of the organization" },
            { name: "accept_url", description: "URL to accept the invitation" }
          ]
        }
      ]

      templates.each do |attrs|
        template = EmailTemplate.find_or_initialize_by(key: attrs[:key])
        template.assign_attributes(attrs.merge(active: true))
        if template.save
          Rails.logger.info "  ✓ #{template.key}"
        else
          Rails.logger.error "  ✗ #{template.key}: #{template.errors.full_messages.join(', ')}"
        end
      end

      Rails.logger.info "Seeded #{EmailTemplate.count} email templates"
    end
  end
end

# Run if called directly
EmailTemplateSeeds.seed! if __FILE__ == $PROGRAM_NAME
