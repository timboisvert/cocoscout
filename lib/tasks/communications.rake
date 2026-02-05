# frozen_string_literal: true

# Communications Validator
# ========================
# This is the source of truth for all communication scenarios in CocoScout.
# Run this task to validate that all communications are correctly configured.
#
# Usage:
#   rails communications:validate           # Run all validations
#   rails communications:validate[verbose]  # Show detailed output
#   rails communications:list               # List all communication scenarios
#   rails communications:audit              # Full audit with recommendations
#   rails communications:by_channel         # Show communications grouped by channel
#   rails communications:stats              # Show statistics
#   rails communications:orphans            # Find orphaned templates (in DB but not in registry)
#
namespace :communications do
  # ============================================
  # COMMUNICATION REGISTRY
  # ============================================
  # This is the canonical list of all communication scenarios.
  # Update this when adding new communications.
  #
  # Structure:
  #   key: The ContentTemplate key (or unique identifier)
  #   name: Human-readable name
  #   category: Topic area (auth, profiles, signups, casting, shows, payments, messages)
  #   channel: Expected channel (email, message, both)
  #   mailer: Mailer class#method (if sends email)
  #   service: Service class (if uses a notification service)
  #   description: What triggers this communication
  #
  COMMUNICATIONS = {
    # ============================================
    # AUTHENTICATION (email-only, users may not have accounts yet)
    # ============================================
    auth_welcome: {
      name: "Welcome Email",
      category: :auth,
      channel: :email,
      mailer: "AuthMailer#signup",
      template_key: "auth_welcome",
      description: "Sent when a new user creates an account",
      callers: [ "AuthController#create" ],
      notes: "Also aliased as 'auth_signup' in database"
    },
    auth_password_reset: {
      name: "Password Reset Email",
      category: :auth,
      channel: :email,
      mailer: "AuthMailer#password",
      template_key: "auth_password_reset",
      description: "Sent when a user requests a password reset",
      callers: [ "PasswordsController#create" ]
    },

    # ============================================
    # PROFILES (invitations, shoutouts, team invites)
    # ============================================
    person_invitation: {
      name: "Person Invitation",
      category: :profiles,
      channel: :email,
      mailer: "Manage::PersonMailer#person_invitation",
      template_key: "person_invitation",
      description: "Invite someone to join an organization on CocoScout",
      callers: [
        "Manage::PeopleController#invite",
        "Manage::PeopleController#invite_existing",
        "Manage::Auditions::CyclesController",
        "ShoutoutsController"
      ]
    },
    group_invitation: {
      name: "Group Invitation",
      category: :profiles,
      channel: :email,
      mailer: "GroupInvitationMailer#invitation",
      template_key: "group_invitation",
      description: "Invite someone to join a group",
      callers: [ "GroupInvitationsController#create" ]
    },
    group_member_added: {
      name: "Added to Group",
      category: :profiles,
      channel: :message,
      service: "MessageService.send_direct",
      template_key: "group_member_added",
      description: "Notify existing user they were added to a group",
      callers: [ "GroupInvitationsController#create" ]
    },
    shoutout_notification: {
      name: "Shoutout Notification",
      category: :profiles,
      channel: :message,
      service: "MessageService.send_direct",
      template_key: "shoutout_notification",
      description: "Notify person they received a shoutout",
      callers: [ "My::ShoutoutsController#send_shoutout_notification" ]
    },
    shoutout_invitation: {
      name: "Shoutout New User Invitation",
      category: :profiles,
      channel: :email,
      mailer: "Manage::PersonMailer#person_invitation",
      template_key: "shoutout_invitation",
      description: "Invite non-user to CocoScout after receiving shoutout",
      callers: [ "My::ShoutoutsController#handle_invite_shoutout" ],
      notes: "Template rendered by caller, passed to mailer as subject/message"
    },
    team_organization_invitation: {
      name: "Team Organization Invitation",
      category: :profiles,
      channel: :email,
      mailer: "Manage::TeamMailer#invite",
      template_key: "team_organization_invitation",
      description: "Invite someone to join organization management team",
      callers: [ "Manage::TeamInvitationsController#create" ],
      notes: "Legacy 'team_invitation' template also exists"
    },
    team_production_invitation: {
      name: "Team Production Invitation",
      category: :profiles,
      channel: :email,
      mailer: "Manage::TeamMailer#production_invite",
      template_key: "team_production_invitation",
      description: "Invite someone to join production management team",
      callers: [ "Manage::TeamInvitationsController#create" ]
    },

    # ============================================
    # SIGN-UPS (registrations, auditions, questionnaires)
    # ============================================
    sign_up_confirmation: {
      name: "Sign-Up Confirmation",
      category: :signups,
      channel: :message,
      service: "SignUpNotificationService",
      template_key: "sign_up_confirmation",
      description: "Confirm user's sign-up registration",
      callers: [ "SignUpRegistrationsController", "SignUpNotificationService" ]
    },
    sign_up_queued: {
      name: "Sign-Up Queued",
      category: :signups,
      channel: :message,
      service: "SignUpNotificationService",
      template_key: "sign_up_queued",
      description: "User added to queue awaiting slot",
      callers: [ "SignUpNotificationService" ]
    },
    sign_up_slot_assigned: {
      name: "Sign-Up Slot Assigned",
      category: :signups,
      channel: :message,
      service: "SignUpNotificationService",
      template_key: "sign_up_slot_assigned",
      description: "User assigned from queue to slot",
      callers: [ "SignUpNotificationService" ]
    },
    sign_up_slot_changed: {
      name: "Sign-Up Slot Changed",
      category: :signups,
      channel: :message,
      service: "SignUpNotificationService",
      template_key: "sign_up_slot_changed",
      description: "User's slot was changed",
      callers: [ "SignUpNotificationService" ]
    },
    sign_up_cancelled: {
      name: "Sign-Up Cancelled",
      category: :signups,
      channel: :message,
      service: "SignUpNotificationService",
      template_key: "sign_up_cancelled",
      description: "User's registration was cancelled",
      callers: [ "SignUpNotificationService" ]
    },
    sign_up_registration_notification: {
      name: "Sign-Up Registration Notification (Producer)",
      category: :signups,
      channel: :message,
      service: "SignUpProducerNotificationService",
      template_key: "sign_up_registration_notification",
      description: "Notify producers of new sign-up registration",
      callers: [ "SignUpProducerNotificationService" ]
    },
    audition_invitation: {
      name: "Audition Invitation",
      category: :signups,
      channel: :message,
      service: "AuditionNotificationService",
      template_key: "audition_invitation",
      description: "Invite talent to audition",
      callers: [ "AuditionNotificationService.send_audition_invitations" ]
    },
    audition_not_invited: {
      name: "Audition Not Invited",
      category: :signups,
      channel: :message,
      service: "AuditionNotificationService",
      template_key: "audition_not_invited",
      description: "Notify person not invited to audition",
      callers: [ "AuditionNotificationService.send_audition_invitations" ]
    },
    audition_request_submitted: {
      name: "Audition Request Submitted",
      category: :signups,
      channel: :message,
      service: "MessageService.send_direct",
      template_key: "audition_request_submitted",
      description: "Notify producers of new audition request",
      callers: [ "AuditionRequestNotificationJob" ]
    },
    talent_left_production: {
      name: "Talent Left Production",
      category: :signups,
      channel: :message,
      service: "MessageService.send_direct",
      template_key: "talent_left_production",
      description: "Notify producers when talent leaves talent pool",
      callers: [ "My::ProductionsController#leave" ]
    },
    questionnaire_invitation: {
      name: "Questionnaire Invitation",
      category: :signups,
      channel: :message,
      service: "MessageService.send_direct",
      template_key: "questionnaire_invitation",
      description: "Invite talent to complete questionnaire",
      callers: [ "Manage::QuestionnairesController#send_invitations" ]
    },

    # ============================================
    # CASTING (audition results, cast notifications)
    # ============================================
    audition_added_to_cast: {
      name: "Audition Added to Cast",
      category: :casting,
      channel: :message,
      service: "AuditionNotificationService",
      template_key: "audition_added_to_cast",
      description: "Notify person they were cast from auditions",
      callers: [ "AuditionNotificationService.send_casting_results" ]
    },
    audition_not_cast: {
      name: "Audition Not Cast",
      category: :casting,
      channel: :message,
      service: "AuditionNotificationService",
      template_key: "audition_not_cast",
      description: "Notify person they weren't cast",
      callers: [ "AuditionNotificationService.send_casting_results" ]
    },
    cast_notification: {
      name: "Cast Notification",
      category: :casting,
      channel: :message,
      service: "CastingNotificationService",
      template_key: "cast_notification",
      description: "Notify person of casting assignment",
      callers: [ "Manage::CastingController#default_cast_email_body" ],
      notes: "Caller-rendered pattern: Controller renders template via ContentTemplateService.render_body/render_subject, passes to service"
    },
    removed_from_cast_notification: {
      name: "Removed from Cast",
      category: :casting,
      channel: :message,
      service: "CastingNotificationService",
      template_key: "removed_from_cast_notification",
      description: "Notify person removed from cast",
      callers: [ "Manage::CastingController#default_removed_email_body" ],
      notes: "Caller-rendered pattern: Controller renders template via ContentTemplateService.render_body/render_subject, passes to service"
    },
    casting_table_notification: {
      name: "Casting Table Notification",
      category: :casting,
      channel: :message,
      service: "MessageService.send_direct",
      template_key: "casting_table_notification",
      description: "Multi-production casting notification from casting table",
      callers: [ "Manage::CastingTablesController#send_casting_notifications" ]
    },

    # ============================================
    # SHOWS (cancellations, vacancies)
    # ============================================
    show_canceled: {
      name: "Show Canceled",
      category: :shows,
      channel: :both,
      mailer: "Manage::ShowMailer#canceled_notification",
      service: "ShowNotificationService",
      template_key: "show_canceled",
      description: "Notify cast of show cancellation",
      callers: [ "ShowNotificationService.send_cancellation_notification" ],
      variables: %w[recipient_name production_name event_type event_date show_name location]
    },
    vacancy_invitation: {
      name: "Vacancy Invitation",
      category: :shows,
      channel: :both,
      mailer: "VacancyInvitationMailer#invitation_email",
      service: "MessageService (in mailer)",
      template_key: "vacancy_invitation",
      description: "Invite person to fill vacant role",
      callers: [ "Manage::VacanciesController", "Manage::RoleVacanciesController" ]
    },
    vacancy_invitation_linked: {
      name: "Vacancy Invitation (Linked Shows)",
      category: :shows,
      channel: :both,
      mailer: "VacancyInvitationMailer#invitation_email",
      service: "MessageService (in mailer)",
      template_key: "vacancy_invitation_linked",
      description: "Invite person to fill vacant role across multiple linked shows",
      callers: [ "Manage::VacanciesController#send_linked_invitations" ],
      notes: "Template rendered by caller, passed to mailer"
    },
    vacancy_created: {
      name: "Vacancy Created",
      category: :shows,
      channel: :both,
      mailer: "VacancyNotificationMailer#vacancy_notification",
      service: "VacancyNotificationService",
      template_key: "vacancy_created",
      description: "Notify team of new vacancy",
      callers: [ "VacancyNotificationService.notify_vacancy_created" ],
      notes: "Service-rendered: VacancyNotificationService renders template via dynamic template_key, passes to mailer"
    },
    vacancy_filled: {
      name: "Vacancy Filled",
      category: :shows,
      channel: :both,
      mailer: "VacancyNotificationMailer#vacancy_notification",
      service: "VacancyNotificationService",
      template_key: "vacancy_filled",
      description: "Notify team vacancy was filled",
      callers: [ "VacancyNotificationService.notify_vacancy_filled" ],
      notes: "Service-rendered: VacancyNotificationService renders template via dynamic template_key, passes to mailer"
    },
    vacancy_reclaimed: {
      name: "Vacancy Reclaimed",
      category: :shows,
      channel: :both,
      mailer: "VacancyNotificationMailer#vacancy_notification",
      service: "VacancyNotificationService",
      template_key: "vacancy_reclaimed",
      description: "Notify team vacancy was reclaimed",
      callers: [ "VacancyNotificationService.notify_vacancy_reclaimed" ],
      notes: "Service-rendered: VacancyNotificationService renders template via dynamic template_key, passes to mailer"
    },

    # ============================================
    # PAYMENTS
    # ============================================
    payment_setup_reminder: {
      name: "Payment Setup Reminder",
      category: :payments,
      channel: :message,
      service: "MessageService.send_direct",
      template_key: "payment_setup_reminder",
      description: "Remind talent to set up payment info",
      callers: [ "Manage::MoneyPayoutsController#send_reminders" ]
    },

    # ============================================
    # CASTING
    # ============================================
    request_agreement_signature: {
      name: "Request Agreement Signature",
      category: :casting,
      channel: :message,
      template_key: "request_agreement_signature",
      description: "Request talent to sign the production agreement",
      callers: [ "Manage::ProductionsController (via view)" ],
      notes: "Template rendered in view via ContentTemplateService.render_body, then sent via compose modal",
      variables: %w[recipient_name production_name agreement_url]
    },

    # ============================================
    # MESSAGES (digests, passthrough)
    # ============================================
    unread_digest: {
      name: "Unread Message Digest",
      category: :messages,
      channel: :email,
      mailer: "MessageNotificationMailer#unread_digest",
      template_key: "unread_digest",
      description: "Digest of unread messages after delay",
      callers: [ "UnreadDigestJob" ]
    }
  }.freeze

  # ============================================
  # LEGACY TEMPLATES (to be cleaned up)
  # ============================================
  # These templates exist in the database but are duplicates or deprecated.
  # They should be removed or consolidated in a future cleanup.
  #
  # - auth_signup: Duplicate of auth_welcome
  # - team_invitation: Legacy version of team_organization_invitation
  # - audition_request_notification: Renamed to audition_request_submitted
  # - shoutout_received: Merged into shoutout_notification
  #
  LEGACY_TEMPLATES = %w[
    auth_signup
    team_invitation
    audition_request_notification
    shoutout_received
  ].freeze

  # ============================================
  # VALIDATION TASKS
  # ============================================

  desc "Validate all communication configurations"
  task :validate, [ :verbose ] => :environment do |_t, args|
    verbose = args[:verbose] == "verbose"
    validator = CommunicationsValidator.new(verbose: verbose)
    validator.run
  end

  desc "List all communication scenarios"
  task list: :environment do
    puts "\n#{"=" * 80}"
    puts "COCOSCOUT COMMUNICATIONS REGISTRY"
    puts "=" * 80

    COMMUNICATIONS.group_by { |_k, v| v[:category] }.sort.each do |category, comms|
      puts "\n#{category.to_s.upcase.ljust(20)} (#{comms.size} communications)"
      puts "-" * 80

      comms.each do |key, config|
        channel_indicator = case config[:channel]
        when :email then "📧"
        when :message then "💬"
        when :both then "📧💬"
        end

        puts "  #{channel_indicator} #{key}"
        puts "     Name: #{config[:name]}"
        puts "     Channel: #{config[:channel]}"
        puts "     Template: #{config[:template_key] || 'N/A'}"
        puts "     Mailer: #{config[:mailer] || 'N/A'}"
        puts "     Service: #{config[:service] || 'N/A'}"
        puts ""
      end
    end

    puts "\n#{"=" * 80}"
    puts "SUMMARY"
    puts "=" * 80
    email_only = COMMUNICATIONS.count { |_k, v| v[:channel] == :email }
    message_only = COMMUNICATIONS.count { |_k, v| v[:channel] == :message }
    both = COMMUNICATIONS.count { |_k, v| v[:channel] == :both }

    puts "  📧 Email-only:    #{email_only}"
    puts "  💬 Message-only:  #{message_only}"
    puts "  📧💬 Both:         #{both}"
    puts "  Total:           #{COMMUNICATIONS.size}"
    puts ""
  end

  desc "Full audit with recommendations"
  task audit: :environment do
    puts "\n#{"=" * 80}"
    puts "COCOSCOUT COMMUNICATIONS AUDIT"
    puts "=" * 80
    puts "Run at: #{Time.current}"
    puts ""

    validator = CommunicationsValidator.new(verbose: true)
    results = validator.run

    if results[:issues].any?
      puts "\n#{"=" * 80}"
      puts "RECOMMENDATIONS"
      puts "=" * 80

      results[:issues].each do |issue|
        puts "\n⚠️  #{issue[:type].to_s.upcase}"
        puts "   Key: #{issue[:key]}"
        puts "   Problem: #{issue[:message]}"
        puts "   Fix: #{issue[:fix]}" if issue[:fix]
      end
    end

    puts "\n#{"=" * 80}"
    puts "AUDIT COMPLETE"
    puts "=" * 80
    puts ""
  end

  # ============================================
  # VALIDATOR CLASS
  # ============================================

  class CommunicationsValidator
    attr_reader :verbose, :issues

    def initialize(verbose: false)
      @verbose = verbose
      @issues = []
      @passed = 0
      @failed = 0
    end

    def run
      puts "\n#{"=" * 60}"
      puts "COMMUNICATIONS VALIDATION"
      puts "=" * 60
      puts ""

      validate_content_templates
      validate_mailers
      validate_services
      validate_channels
      validate_code_wiring
      validate_template_variables
      validate_liquid_syntax
      validate_code_provides_variables
      validate_registry_coverage

      print_summary
      { passed: @passed, failed: @failed, issues: @issues }
    end

    private

    def validate_content_templates
      puts "📋 ContentTemplates"

      COMMUNICATIONS.each do |key, config|
        next unless config[:template_key]

        template = ContentTemplate.find_by(key: config[:template_key])

        if template.nil?
          add_issue(:missing_template, key, "ContentTemplate '#{config[:template_key]}' not found in database",
                    "Run migrations or add template via seeds")
          next
        end

        # Check channel matches
        expected_channel = config[:channel].to_s
        if template.channel != expected_channel
          add_issue(:channel_mismatch, key,
                    "Template channel is '#{template.channel}' but expected '#{expected_channel}'",
                    "Update ContentTemplate.where(key: '#{config[:template_key]}').update_all(channel: '#{expected_channel}')")
        else
          pass("#{config[:template_key]} (#{expected_channel})")
        end

        # Check category
        valid_categories = ContentTemplate::CATEGORIES
        if template.category.present? && !valid_categories.include?(template.category)
          add_issue(:invalid_category, key,
                    "Template category '#{template.category}' is not valid (expected: #{config[:category]})",
                    "Valid categories: #{valid_categories.join(', ')}")
        end
      end
      puts ""
    end

    def validate_mailers
      puts "📧 Mailers"

      COMMUNICATIONS.each do |key, config|
        next unless config[:mailer]

        mailer_class, method_name = config[:mailer].split("#")

        # Check mailer class exists
        begin
          klass = mailer_class.constantize
        rescue NameError
          add_issue(:missing_mailer, key, "Mailer class '#{mailer_class}' not found",
                    "Create the mailer or remove it from registry")
          next
        end

        # Check method exists
        if klass.instance_methods(false).include?(method_name.to_sym) ||
           klass.method_defined?(method_name.to_sym)
          pass("#{config[:mailer]}")
        else
          add_issue(:missing_mailer_method, key, "Mailer method '#{method_name}' not found in #{mailer_class}",
                    "Add the method or remove from registry")
        end
      end
      puts ""
    end

    def validate_services
      puts "⚙️  Services"

      COMMUNICATIONS.each do |key, config|
        next unless config[:service]

        service_name = config[:service].split(".").first.split("(").first

        begin
          service_name.constantize
          pass("#{service_name}")
        rescue NameError
          # It might be a method on a service
          if service_name.include?("::")
            add_issue(:missing_service, key, "Service '#{service_name}' not found",
                      "Create the service or update registry")
          end
        end
      end
      puts ""
    end

    def validate_channels
      puts "🔀 Channel Configuration"

      # Check email-only communications have mailers
      COMMUNICATIONS.each do |key, config|
        if config[:channel] == :email && config[:mailer].nil?
          add_issue(:email_no_mailer, key, "Email-only communication has no mailer defined",
                    "Add mailer or change channel to :message")
        end

        if config[:channel] == :message && config[:mailer].present? && config[:service].nil?
          add_issue(:message_with_mailer, key, "Message-only communication should not send email",
                    "Remove mailer call or add service for message delivery")
        end

        if config[:channel] == :both
          if config[:mailer].nil?
            add_issue(:both_no_mailer, key, "Both channel needs a mailer",
                      "Add mailer configuration")
          end
          if config[:service].nil?
            add_issue(:both_no_service, key, "Both channel needs a message service",
                      "Add service for message delivery")
          else
            pass("#{key} (email + message)")
          end
        end
      end
      puts ""
    end

    # ============================================
    # DEEP CODE WIRING VALIDATION
    # ============================================
    # Verifies that mailers and services are actually calling
    # ContentTemplateService.render with the correct template key,
    # and that message services call MessageService.send_direct.

    def validate_code_wiring
      puts "🔌 Code Wiring"

      COMMUNICATIONS.each do |key, config|
        template_key = config[:template_key]
        next unless template_key

        case config[:channel]
        when :email
          validate_email_wiring(key, config)
        when :message
          validate_message_wiring(key, config)
        when :both
          validate_both_wiring(key, config)
        end
      end
      puts ""
    end

    def validate_email_wiring(key, config)
      return unless config[:mailer]

      mailer_class, method_name = config[:mailer].split("#")
      template_key = config[:template_key]

      # Check if this is a caller-rendered pattern (noted in config)
      if config[:notes]&.include?("caller") || config[:notes]&.include?("Caller")
        validate_caller_wiring(key, config, suffix: "→ mailer")
        return
      end

      # Check if this is a service-rendered pattern (noted in config)
      if config[:notes]&.include?("Service-rendered") || config[:notes]&.include?("service-rendered")
        validate_service_template_rendering(key, config)
        return
      end

      # Find the mailer file
      mailer_path = find_mailer_file(mailer_class)
      return add_issue(:mailer_file_not_found, key, "Cannot find mailer file for #{mailer_class}") unless mailer_path

      content = File.read(mailer_path)

      # Check mailer uses ContentTemplateService with correct template key
      if content.include?("ContentTemplateService")
        # Check for the correct template key
        if content.match?(/ContentTemplateService\.render\s*\(\s*["']#{Regexp.escape(template_key)}["']/) ||
           content.match?(/ContentTemplateService\.render_subject\s*\(\s*["']#{Regexp.escape(template_key)}["']/)
          pass("#{key} mailer → #{template_key}")
        else
          # It uses ContentTemplateService but maybe with wrong key
          found_keys = content.scan(/ContentTemplateService\.render(?:_subject)?\s*\(\s*["']([^"']+)["']/).flatten
          add_issue(:mailer_wrong_template, key,
                    "Mailer uses ContentTemplateService but not with '#{template_key}' (found: #{found_keys.join(', ')})",
                    "Update mailer to use ContentTemplateService.render('#{template_key}', ...)")
        end
      elsif content.match?(/params\[:subject\]|@subject\s*=\s*params\[:subject\]/)
        # Mailer receives pre-rendered content from service - check service renders template
        if config[:service]
          service_name = config[:service].split(".").first.split("(").first
          service_path = find_service_file(service_name)
          if service_path
            service_content = File.read(service_path)
            # Check if service renders this specific template, or uses dynamic template_key
            if service_content.match?(/ContentTemplateService\.render\s*\(\s*["']#{Regexp.escape(template_key)}["']/) ||
               (service_content.include?("ContentTemplateService.render") && service_content.include?("\"#{template_key}\""))
              pass("#{key} service → mailer (pre-rendered)")
            else
              add_issue(:service_wrong_template, key,
                        "Service #{service_name} should render '#{template_key}' before calling mailer",
                        "Service must use ContentTemplateService.render('#{template_key}', ...) before passing to mailer")
            end
          else
            add_issue(:mailer_no_content_service, key,
                      "Mailer receives pre-rendered content but no service file found",
                      "Verify service renders '#{template_key}' via ContentTemplateService")
          end
        else
          pass("#{key} mailer receives pre-rendered content")
        end
      else
        add_issue(:mailer_no_content_service, key,
                  "Mailer #{mailer_class}##{method_name} doesn't use ContentTemplateService",
                  "Mailer must use ContentTemplateService.render('#{template_key}', ...) for content")
      end
    end

    def validate_message_wiring(key, config)
      return unless config[:service]
      template_key = config[:template_key]
      service_ref = config[:service]
      service_name = service_ref.split(".").first

      # Check if this is a caller-rendered pattern (noted in config)
      if config[:notes]&.include?("caller") || config[:notes]&.include?("Caller")
        validate_caller_wiring(key, config)
        return
      end

      # Two patterns:
      # 1. Dedicated service (e.g., SignUpNotificationService) - service renders template
      # 2. MessageService.send_direct - caller renders template, check callers

      if service_ref.include?("MessageService.send_direct") || service_ref.include?("MessageService (")
        # Generic MessageService - check callers for template rendering
        validate_caller_wiring(key, config)
      else
        # Dedicated service - check service file for template rendering
        service_path = find_service_file(service_name)
        return add_issue(:service_file_not_found, key, "Cannot find service file for #{service_name}") unless service_path

        content = File.read(service_path)

        # Check service uses ContentTemplateService with correct template key
        # Handles multiple patterns:
        # 1. Direct string: ContentTemplateService.render("template_key", ...)
        # 2. Variable: ContentTemplateService.render(template_key, ...) with template_key = "..."
        # 3. Hash: TEMPLATE_KEYS = { ... :template_key => "..." } or template_key: "..."
        # 4. Constant: TEMPLATE_KEY = "template_key"
        template_ok = content.match?(/ContentTemplateService\.render\s*\(\s*["']#{Regexp.escape(template_key)}["']/) ||
                      (content.include?("ContentTemplateService.render") &&
                       (content.include?("\"#{template_key}\"") || content.include?("'#{template_key}'")))

        # Check service calls MessageService.send_direct
        message_ok = content.include?("MessageService.send_direct") ||
                     content.include?("MessageService.send_to_")

        if template_ok && message_ok
          pass("#{key} service → #{template_key} + MessageService")
        elsif !template_ok
          add_issue(:service_wrong_template, key,
                    "Service #{service_name} doesn't render template '#{template_key}'",
                    "Service must use ContentTemplateService.render('#{template_key}', ...) for content")
        elsif !message_ok
          add_issue(:service_no_message_call, key,
                    "Service #{service_name} doesn't call MessageService.send_direct",
                    "Message-only communications must call MessageService.send_direct to deliver")
        end
      end
    end

    def validate_caller_wiring(key, config, suffix: "+ MessageService.send_direct")
      template_key = config[:template_key]
      callers = config[:callers] || []

      return add_issue(:no_callers_defined, key, "No callers defined for communication") if callers.empty?

      # Check each caller location for ContentTemplateService.render with the template key
      found_in_any_caller = false

      callers.each do |caller_ref|
        # Parse caller reference: "SomeController#method" or "SomeService.method" or just "SomeClass"
        caller_path = find_caller_file(caller_ref)
        next unless caller_path && File.exist?(caller_path)

        content = File.read(caller_path)
        if content.match?(/ContentTemplateService\.render(?:_subject|_body)?\s*\(\s*["']#{Regexp.escape(template_key)}["']/)
          found_in_any_caller = true
          break
        end
      end

      if found_in_any_caller
        pass("#{key} caller → #{template_key} #{suffix}")
      else
        add_issue(:caller_missing_template, key,
                  "No caller renders template '#{template_key}' via ContentTemplateService",
                  "Add ContentTemplateService.render('#{template_key}', ...) at caller: #{callers.join(', ')}")
      end
    end

    def validate_service_template_rendering(key, config)
      # For service-rendered patterns, check the service renders the template
      # Mailer receives pre-rendered content from service
      return unless config[:service]

      template_key = config[:template_key]
      service_name = config[:service].split(".").first.split("(").first
      service_path = find_service_file(service_name)

      return add_issue(:service_file_not_found, key, "Cannot find service file for #{service_name}") unless service_path

      content = File.read(service_path)

      # Check if service uses ContentTemplateService with the correct template key
      # Handle dynamic template_key pattern (case statement, etc.)
      template_ok = content.match?(/ContentTemplateService\.render\s*\(\s*["']#{Regexp.escape(template_key)}["']/) ||
                    (content.include?("ContentTemplateService.render") &&
                     (content.include?("\"#{template_key}\"") || content.include?("'#{template_key}'")))

      if template_ok
        pass("#{key} service → mailer (pre-rendered)")
      else
        add_issue(:service_wrong_template, key,
                  "Service #{service_name} doesn't render template '#{template_key}'",
                  "Service must use ContentTemplateService.render('#{template_key}', ...) before passing to mailer")
      end
    end

    def find_caller_file(caller_ref)
      # Parse caller reference and find the file
      # "SomeController#method" -> app/controllers/some_controller.rb
      # "Manage::SomeController#method" -> app/controllers/manage/some_controller.rb
      # "SomeService" -> app/services/some_service.rb
      # "SomeJob" -> app/jobs/some_job.rb

      class_name = caller_ref.split("#").first.split(".").first

      # Try different locations
      file_name = class_name.underscore + ".rb"

      paths_to_try = [
        Rails.root.join("app/controllers", file_name),
        Rails.root.join("app/services", file_name),
        Rails.root.join("app/jobs", file_name),
        Rails.root.join("app/models", file_name)
      ]

      paths_to_try.find { |p| File.exist?(p) }
    end

    def validate_both_wiring(key, config)
      # For "both" channels, validate both email and message wiring
      template_key = config[:template_key]

      # Check mailer wiring (email portion)
      if config[:mailer]
        validate_email_wiring(key, config)
      end

      # Check service wiring (message portion)
      if config[:service] && !config[:service].include?("(in mailer)")
        validate_message_wiring(key, config)
      elsif config[:service]&.include?("(in mailer)")
        # Service is in the mailer - check mailer calls MessageService
        mailer_class, _method_name = config[:mailer].split("#")
        mailer_path = find_mailer_file(mailer_class)
        if mailer_path
          content = File.read(mailer_path)
          if content.include?("MessageService.send_direct") || content.include?("MessageService.send_to_")
            pass("#{key} mailer includes MessageService")
          else
            add_issue(:both_missing_message, key,
                      "Mailer for 'both' channel doesn't call MessageService",
                      "Add MessageService.send_direct call to send in-app message")
          end
        end
      end
    end

    def validate_template_variables
      puts "📝 Template Variables"

      COMMUNICATIONS.each do |key, config|
        next unless config[:template_key]

        template = ContentTemplate.find_by(key: config[:template_key])
        next unless template

        # Get variables used in the template content
        used_vars = template.variable_names

        # Get documented available variables
        available_vars = (template.available_variables || []).map do |v|
          if v.is_a?(Hash)
            (v[:name] || v["name"]).to_s
          else
            v.to_s
          end
        end

        # Check for variables used but not documented
        undocumented = used_vars - available_vars
        if undocumented.any?
          add_issue(:undocumented_variables, key,
                    "Template uses variables not in available_variables: #{undocumented.join(', ')}",
                    "Update ContentTemplate.available_variables or remove from template content")
        end

        # Check for documented variables that aren't used (warning only, not a failure)
        unused = available_vars - used_vars
        if unused.any? && @verbose
          puts "  ℹ️  #{key}: Documented but unused variables: #{unused.join(', ')}"
        end

        if undocumented.empty?
          pass("#{key} variables documented")
        end
      end
      puts ""
    end

    def validate_liquid_syntax
      puts "🧪 Template Syntax"

      COMMUNICATIONS.each do |key, config|
        next unless config[:template_key]

        template = ContentTemplate.find_by(key: config[:template_key])
        next unless template

        errors = []

        # Check subject template syntax
        errors.concat(check_mustache_syntax(template.subject, "Subject"))

        # Check body template syntax
        errors.concat(check_mustache_syntax(template.body, "Body"))

        # Also check message_body if present (for dual-channel templates)
        errors.concat(check_mustache_syntax(template.message_body, "Message body"))

        if errors.any?
          add_issue(:template_syntax_error, key,
                    "Template syntax error: #{errors.join('; ')}",
                    "Fix the template syntax in ContentTemplate '#{config[:template_key]}'")
        else
          pass("#{key} syntax valid")
        end
      end
      puts ""
    end

    # Check mustache-style template syntax: {{ var }} and {{#var}}...{{/var}}
    def check_mustache_syntax(text, field_name)
      return [] if text.blank?

      errors = []

      # Check for unbalanced opening braces ({{ without }})
      opens = text.scan(/\{\{/).count
      closes = text.scan(/\}\}/).count
      if opens != closes
        errors << "#{field_name}: Unbalanced braces (#{opens} opens, #{closes} closes)"
      end

      # Check for conditional blocks - {{#var}} must have matching {{/var}}
      opening_blocks = text.scan(/\{\{#(\w+)\}\}/).flatten
      closing_blocks = text.scan(/\{\{\/(\w+)\}\}/).flatten

      # Check for unclosed blocks
      unclosed = opening_blocks - closing_blocks
      if unclosed.any?
        errors << "#{field_name}: Unclosed conditional block(s): #{unclosed.map { |v| "{{##{v}}}" }.join(', ')}"
      end

      # Check for unmatched closing blocks
      unmatched = closing_blocks - opening_blocks
      if unmatched.any?
        errors << "#{field_name}: Unmatched closing block(s): #{unmatched.map { |v| "{{/#{v}}}" }.join(', ')}"
      end

      # Check for nested blocks with same variable (not supported)
      opening_blocks.each do |var|
        if text.scan(/\{\{##{var}\}\}/).count > 1
          errors << "#{field_name}: Nested/duplicate conditional block: {{##{var}}}"
        end
      end

      errors
    end

    # This is the critical validation - ensures code provides what templates use
    def validate_code_provides_variables
      puts "🔗 Code → Template Variable Alignment"

      # Build a map of template_key -> variables the code provides
      code_variables = extract_code_variables

      COMMUNICATIONS.each do |key, config|
        next unless config[:template_key]
        template_key = config[:template_key]

        template = ContentTemplate.find_by(key: template_key)
        next unless template

        # Get variables used in the template content
        used_vars = template.variable_names

        # Get variables the code provides (from static analysis)
        provided_vars = code_variables[template_key] || []

        # If code tracing failed, check if registry has variables defined
        if provided_vars.empty? && config[:variables].present?
          provided_vars = config[:variables].map(&:to_s)
        end

        # If we couldn't find code for this template, skip (other validations cover this)
        if provided_vars.empty?
          # Check if this is a passthrough/hybrid template where content comes from user
          if template.passthrough? || template.hybrid?
            pass("#{key} (passthrough/hybrid)")
            next
          end
          # Otherwise we couldn't trace the code - warn but don't fail
          puts "  ℹ️  #{key}: Could not trace code variables (manual review needed)"
          next
        end

        # Check for variables used in template but not provided by code
        missing_from_code = used_vars - provided_vars
        if missing_from_code.any?
          add_issue(:code_missing_variables, key,
                    "Template uses variables not provided by code: #{missing_from_code.join(', ')}",
                    "Update code to pass these variables to ContentTemplateService.render")
        else
          pass("#{key} code provides all variables")
        end
      end
      puts ""
    end

    # Extract variables from code that calls ContentTemplateService.render
    def extract_code_variables
      variables = {}

      # Scan all relevant files for ContentTemplateService.render calls
      %w[app/controllers app/services app/jobs app/mailers].each do |dir|
        Dir.glob(Rails.root.join(dir, "**", "*.rb")).each do |file|
          content = File.read(file)
          next unless content.include?("ContentTemplateService")

          # Check for TEMPLATE_KEY constant pattern: TEMPLATE_KEY = "literal" ... render(TEMPLATE_KEY, { variables })
          if content =~ /TEMPLATE_KEY\s*=\s*["']([^"']+)["']/
            template_key = $1
            variables[template_key] ||= []

            # Find inline variables hash: render(TEMPLATE_KEY, { var1: ..., var2: ... })
            if (inline_match = content.match(/ContentTemplateService\.render\s*\(\s*TEMPLATE_KEY\s*,\s*\{/m))
              pos = inline_match.end(0)
              brace_count = 1
              end_pos = pos
              while brace_count > 0 && end_pos < content.length
                case content[end_pos]
                when "{" then brace_count += 1
                when "}" then brace_count -= 1
                end
                end_pos += 1
              end
              var_hash = content[pos...end_pos - 1]
              var_names = var_hash.scan(/(\w+):/).flatten
              variables[template_key].concat(var_names).uniq!
            end

            # Find build_template_variables method or variables hash
            if (vars_match = content.match(/def\s+build_template_variables.*?\{/m))
              pos = vars_match.end(0)
              brace_count = 1
              end_pos = pos
              while brace_count > 0 && end_pos < content.length
                case content[end_pos]
                when "{" then brace_count += 1
                when "}" then brace_count -= 1
                end
                end_pos += 1
              end
              var_hash = content[pos...end_pos - 1]
              var_names = var_hash.scan(/(\w+):/).flatten
              variables[template_key].concat(var_names).uniq!
            end

            # Also check for base_variables.merge(recipient_name: ...) pattern
            content.scan(/\.merge\s*\(\s*\n?\s*(\w+):/) do |merge_match|
              variables[template_key] << merge_match[0]
            end
            variables[template_key].uniq!
          end

          # Find all render calls with their template keys and variable hashes
          # Pattern: ContentTemplateService.render("template_key", { var1: ..., var2: ... })
          # Also: ContentTemplateService.render_body/render_subject

          # Use a more robust approach: find template key, then find the balanced braces
          content.scan(/ContentTemplateService\.render(?:_body|_subject)?\s*\(\s*["']([^"']+)["']\s*,\s*\{/m) do |match|
            template_key = match[0]
            # Find the position after the opening brace
            pos = Regexp.last_match.end(0)
            # Extract content until balanced closing brace
            brace_count = 1
            end_pos = pos
            while brace_count > 0 && end_pos < content.length
              case content[end_pos]
              when "{" then brace_count += 1
              when "}" then brace_count -= 1
              end
              end_pos += 1
            end
            var_hash = content[pos...end_pos - 1]

            # Extract variable names from the hash (keys before the colon)
            var_names = var_hash.scan(/(\w+):/).flatten
            variables[template_key] ||= []
            variables[template_key].concat(var_names).uniq!
          end

          # Also handle cases where variables are built separately
          # Look for: variables = { ... } followed by render(key, variables)
          content.scan(/(\w+)\s*=\s*\{([^}]+)\}.*?ContentTemplateService\.render(?:_body|_subject)?\s*\(\s*["']([^"']+)["']\s*,\s*\1/m) do |match|
            var_hash = match[1]
            template_key = match[2]

            var_names = var_hash.scan(/(\w+):/).flatten
            variables[template_key] ||= []
            variables[template_key].concat(var_names).uniq!
          end

          # Handle pattern where template_key is passed to a helper method that calls render
          # Look for: template_key: "literal_key" ... extra_variables: { ... }
          # This catches VacancyNotificationService pattern
          content.scan(/template_key:\s*["']([^"']+)["'].*?extra_variables:\s*\{([^}]+)\}/m) do |match|
            template_key = match[0]
            extra_hash = match[1]

            var_names = extra_hash.scan(/(\w+):/).flatten
            variables[template_key] ||= []
            variables[template_key].concat(var_names).uniq!
          end

          # Handle pattern: method calls helper with template_key: "literal",
          # and helper has variables = { ... } then calls render(template_key, variables)
          # This catches SignUpNotificationService pattern
          if content.include?("template_key:") && content.include?("ContentTemplateService.render(template_key")
            # Find all template_key: "literal" patterns
            template_keys_in_file = content.scan(/template_key:\s*["']([^"']+)["']/).flatten.uniq

            # Find the variables hash (may be multiline with balanced braces)
            if (vars_match = content.match(/variables\s*=\s*\{/))
              pos = vars_match.end(0)
              brace_count = 1
              end_pos = pos
              while brace_count > 0 && end_pos < content.length
                case content[end_pos]
                when "{" then brace_count += 1
                when "}" then brace_count -= 1
                end
                end_pos += 1
              end
              var_hash = content[pos...end_pos - 1]
              var_names = var_hash.scan(/(\w+):/).flatten

              # Apply these variables to all template_keys in this file
              template_keys_in_file.each do |tk|
                variables[tk] ||= []
                variables[tk].concat(var_names).uniq!
              end
            end
          end

          # Also find base_variables in the same file and merge them
          if content.include?("base_variables")
            base_vars = []

            # Extract base_variables hash (may be multiline with balanced braces)
            if (start_match = content.match(/base_variables\s*=\s*\{/))
              pos = start_match.end(0)
              brace_count = 1
              end_pos = pos
              while brace_count > 0 && end_pos < content.length
                case content[end_pos]
                when "{" then brace_count += 1
                when "}" then brace_count -= 1
                end
                end_pos += 1
              end
              base_hash = content[pos...end_pos - 1]
              base_vars = base_hash.scan(/(\w+):/).flatten
            end

            # Also look for variables merged into base_variables later
            # Pattern: variables = base_variables.merge(key: value, ...)
            # or: .merge(\n  recipient_name: ...)
            content.scan(/\.merge\s*\(\s*\{?\s*(\w+):/m) do |merge_match|
              base_vars << merge_match[0]
            end
            content.scan(/\.merge\s*\(\s*\n\s*(\w+):/m) do |merge_match|
              base_vars << merge_match[0]
            end

            # Apply base_vars to any template_key found in this file
            content.scan(/template_key:\s*["']([^"']+)["']/) do |key_match|
              template_key = key_match[0]
              variables[template_key] ||= []
              variables[template_key].concat(base_vars).uniq!
            end
          end
        end
      end

      variables
    end

    def validate_registry_coverage
      puts "🗂️  Registry Coverage"

      # Get all template keys from registry
      registered_keys = COMMUNICATIONS.map { |_k, v| v[:template_key] }.compact

      # Get all template keys from database
      db_keys = ContentTemplate.pluck(:key)

      # Find missing templates (in registry but not in DB) - THIS BLOCKS DEPLOY
      missing = registered_keys - db_keys

      if missing.any?
        missing.each do |missing_key|
          add_issue(:missing_template_in_db, missing_key,
                    "Template '#{missing_key}' is in registry but NOT in database",
                    "Create the template in dev DB before exporting to production")
        end
      else
        pass("All #{registered_keys.count} registered templates exist in database")
      end

      # Find orphans (in DB but not in registry) - just informational
      orphans = db_keys - registered_keys

      if orphans.any?
        puts "  ℹ️  #{orphans.count} orphan template(s) in DB not in registry: #{orphans.join(', ')}"
        puts "     (These won't block deploy but consider cleanup)"
      end
      puts ""
    end

    def find_mailer_file(mailer_class)
      # Convert class name to file path
      # "Manage::TeamMailer" -> "app/mailers/manage/team_mailer.rb"
      file_name = mailer_class.underscore + ".rb"
      path = Rails.root.join("app/mailers", file_name)
      File.exist?(path) ? path : nil
    end

    def find_service_file(service_name)
      # Convert class name to file path
      # "SignUpNotificationService" -> "app/services/sign_up_notification_service.rb"
      file_name = service_name.underscore + ".rb"
      path = Rails.root.join("app/services", file_name)
      File.exist?(path) ? path : nil
    end

    def add_issue(type, key, message, fix = nil)
      @issues << { type: type, key: key, message: message, fix: fix }
      @failed += 1
      puts "  ❌ #{key}: #{message}"
    end

    def pass(message)
      @passed += 1
      puts "  ✅ #{message}"
    end

    def print_summary
      puts "#{"=" * 60}"
      puts "SUMMARY"
      puts "=" * 60
      puts "  ✅ Passed: #{@passed}"
      puts "  ❌ Failed: #{@failed}"

      if @issues.any?
        puts "\n  Issues by type:"
        @issues.group_by { |i| i[:type] }.each do |type, issues|
          puts "    #{type}: #{issues.size}"
        end
      else
        puts "\n  All communications are correctly configured! 🎉"
      end
      puts ""
    end
  end

  # ============================================
  # ADDITIONAL ANALYSIS TASKS
  # ============================================

  desc "Show communications grouped by channel"
  task by_channel: :environment do
    puts "\n#{"=" * 80}"
    puts "COMMUNICATIONS BY CHANNEL"
    puts "=" * 80

    { email: "📧 EMAIL-ONLY", message: "💬 MESSAGE-ONLY", both: "📧💬 BOTH" }.each do |channel, label|
      comms = COMMUNICATIONS.select { |_k, v| v[:channel] == channel }
      puts "\n#{label} (#{comms.size})"
      puts "-" * 60

      comms.group_by { |_k, v| v[:category] }.sort.each do |category, cat_comms|
        puts "  #{category.to_s.upcase}:"
        cat_comms.each do |key, config|
          puts "    - #{key}: #{config[:name]}"
        end
      end
    end
    puts ""
  end

  desc "Show communication statistics"
  task stats: :environment do
    puts "\n#{"=" * 80}"
    puts "COMMUNICATION STATISTICS"
    puts "=" * 80

    # By channel
    puts "\nBy Channel:"
    puts "  📧 Email-only:    #{COMMUNICATIONS.count { |_k, v| v[:channel] == :email }}"
    puts "  💬 Message-only:  #{COMMUNICATIONS.count { |_k, v| v[:channel] == :message }}"
    puts "  📧💬 Both:         #{COMMUNICATIONS.count { |_k, v| v[:channel] == :both }}"

    # By category
    puts "\nBy Category:"
    COMMUNICATIONS.group_by { |_k, v| v[:category] }.sort.each do |category, comms|
      puts "  #{category.to_s.ljust(15)}: #{comms.size}"
    end

    # Mailers in use
    mailers = COMMUNICATIONS.filter_map { |_k, v| v[:mailer]&.split("#")&.first }.uniq.sort
    puts "\nMailers in Use (#{mailers.size}):"
    mailers.each { |m| puts "  - #{m}" }

    # Services in use
    services = COMMUNICATIONS.filter_map { |_k, v| v[:service]&.split(".")&.first&.split("(")&.first }.uniq.sort
    puts "\nServices in Use (#{services.size}):"
    services.each { |s| puts "  - #{s}" }

    puts "\nTotal Communications: #{COMMUNICATIONS.size}"
    puts ""
  end

  desc "Find orphaned templates (in database but not in registry)"
  task orphans: :environment do
    puts "\n#{"=" * 80}"
    puts "ORPHANED TEMPLATE CHECK"
    puts "=" * 80
    puts ""
    puts "Orphaned templates are ContentTemplate records in the database that are NOT"
    puts "registered in the COMMUNICATIONS registry. This can happen when:"
    puts "  • A template was created manually but never added to the registry"
    puts "  • A template was renamed but the old version wasn't cleaned up"
    puts "  • A feature was removed but its template wasn't deleted"
    puts ""
    puts "Legacy templates are known deprecated templates scheduled for removal."
    puts ""

    registered_keys = COMMUNICATIONS.map { |_k, v| v[:template_key] }.compact
    db_keys = ContentTemplate.pluck(:key)

    orphans = db_keys - registered_keys - LEGACY_TEMPLATES
    legacy_found = db_keys & LEGACY_TEMPLATES
    missing = registered_keys - db_keys

    if legacy_found.any?
      puts "📋 Legacy templates in database (#{legacy_found.size}):"
      puts "   These are deprecated templates that can be safely deleted."
      legacy_found.sort.each do |key|
        template = ContentTemplate.find_by(key: key)
        puts "  - #{key} (#{template&.channel})"
      end
      puts ""
      puts "   💡 Run: rake communications:cleanup_legacy"
      puts ""
    end

    if orphans.any?
      puts "⚠️  Unknown templates in database (#{orphans.size}):"
      puts "   These need investigation - either add to registry or delete."
      orphans.sort.each do |key|
        template = ContentTemplate.find_by(key: key)
        puts "  - #{key} (category: #{template&.category}, channel: #{template&.channel})"
      end
      puts "\n  Action needed:"
      puts "    - If actively used: Add to COMMUNICATIONS registry"
      puts "    - If deprecated: Add to LEGACY_TEMPLATES for tracking"
      puts "    - If unused: Delete from database"
      puts ""
    elsif legacy_found.empty?
      puts "✅ No orphaned or legacy templates found"
      puts ""
    else
      puts "✅ No unknown orphaned templates"
      puts "   Legacy templates above can be cleaned up when ready."
      puts ""
    end

    if missing.any?
      puts "❌ Templates in registry but NOT in database (#{missing.size}):"
      missing.sort.each do |key|
        puts "  - #{key}"
      end
      puts "\n  Run migrations to create these templates"
      puts ""
    end
  end

  desc "Generate markdown documentation"
  task docs: :environment do
    puts "# CocoScout Communications Reference"
    puts ""
    puts "Auto-generated on #{Time.current.strftime('%Y-%m-%d %H:%M')}"
    puts ""
    puts "## Summary"
    puts ""
    puts "| Channel | Count |"
    puts "|---------|-------|"
    puts "| Email-only | #{COMMUNICATIONS.count { |_k, v| v[:channel] == :email }} |"
    puts "| Message-only | #{COMMUNICATIONS.count { |_k, v| v[:channel] == :message }} |"
    puts "| Both | #{COMMUNICATIONS.count { |_k, v| v[:channel] == :both }} |"
    puts "| **Total** | **#{COMMUNICATIONS.size}** |"
    puts ""

    COMMUNICATIONS.group_by { |_k, v| v[:category] }.sort.each do |category, comms|
      puts "## #{category.to_s.titleize}"
      puts ""
      puts "| Key | Name | Channel | Mailer | Service |"
      puts "|-----|------|---------|--------|---------|"

      comms.sort_by { |k, _v| k }.each do |key, config|
        channel = case config[:channel]
        when :email then "📧 Email"
        when :message then "💬 Message"
        when :both then "📧💬 Both"
        end
        mailer = config[:mailer] || "-"
        service = config[:service] || "-"
        puts "| `#{key}` | #{config[:name]} | #{channel} | `#{mailer}` | `#{service}` |"
      end
      puts ""
    end
  end

  desc "Check for potential issues in communication code"
  task code_check: :environment do
    puts "\n#{"=" * 80}"
    puts "COMMUNICATION CODE CHECK"
    puts "=" * 80

    issues = []
    warnings = []

    # Check for deliver_now (should usually be deliver_later)
    puts "\n📧 Checking for deliver_now usage..."
    Dir.glob(Rails.root.join("app/**/*.rb")).each do |file|
      content = File.read(file)
      if content.include?(".deliver_now")
        relative = file.sub(Rails.root.to_s + "/", "")
        # deliver_now in tests is fine
        unless relative.include?("spec/") || relative.include?("test/")
          warnings << { file: relative, issue: "Uses deliver_now (blocking)" }
        end
      end
    end

    # Check for direct mailer calls that should go through services
    puts "📋 Checking for direct mailer calls in controllers..."
    Dir.glob(Rails.root.join("app/controllers/**/*.rb")).each do |file|
      content = File.read(file)
      if content.match?(/Mailer\..*\.deliver/)
        relative = file.sub(Rails.root.to_s + "/", "")
        warnings << { file: relative, issue: "Direct mailer call (consider service extraction)" }
      end
    end

    # Check that all mailers use ContentTemplateService
    puts "🔍 Checking mailers use ContentTemplateService..."
    mailer_files = Dir.glob(Rails.root.join("app/mailers/**/*.rb"))
    mailer_files.each do |file|
      relative = file.sub(Rails.root.to_s + "/", "")
      content = File.read(file)

      # Skip ApplicationMailer base class and AppMailer helper
      next if relative.include?("application_mailer.rb")
      next if relative.include?("app_mailer.rb")

      # Check if mailer has methods that send email
      if content.match?(/def\s+\w+.*\n.*mail\s*\(/) || content.match?(/def\s+\w+.*\n.*mail\(/)
        # Check if it uses ContentTemplateService
        unless content.include?("ContentTemplateService")
          issues << { file: relative, issue: "Mailer sends email without using ContentTemplateService" }
        end
      end
    end

    if warnings.any?
      puts "\n⚠️  Warnings (not blocking):"
      warnings.each do |w|
        puts "  - #{w[:file]}: #{w[:issue]}"
      end
    end

    if issues.any?
      puts "\n❌ Issues Found (must fix):"
      issues.each do |issue|
        puts "  - #{issue[:file]}: #{issue[:issue]}"
      end
      puts "\n  All mailers MUST use ContentTemplateService for email content."
      puts "  This ensures templates are editable in the admin and consistent."
    else
      puts "\n✅ All mailers correctly use ContentTemplateService"
    end

    puts ""
  end

  desc "Delete legacy templates from database"
  task cleanup_legacy: :environment do
    puts "\n#{"=" * 80}"
    puts "LEGACY TEMPLATE CLEANUP"
    puts "=" * 80

    legacy_found = ContentTemplate.where(key: LEGACY_TEMPLATES)

    if legacy_found.empty?
      puts "\n✅ No legacy templates to clean up"
    else
      puts "\nThe following legacy templates will be deleted:"
      legacy_found.each do |t|
        puts "  - #{t.key} (#{t.name})"
      end

      print "\nProceed with deletion? (yes/no): "
      confirm = $stdin.gets&.chomp

      if confirm&.downcase == "yes"
        count = legacy_found.destroy_all.size
        puts "\n✅ Deleted #{count} legacy templates"
      else
        puts "\n⏭️  Cleanup cancelled"
      end
    end

    puts ""
  end
end
