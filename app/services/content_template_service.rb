# frozen_string_literal: true

# Unified service for rendering content templates across email and messaging channels.
#
# This service wraps ContentTemplate and determines how content should be delivered
# based on the template's channel setting:
#   - email: Send via email only
#   - message: Create in-app message only
#   - both: Create message AND send email notification
#
# Usage:
#   # Render and get delivery instructions
#   result = ContentTemplateService.render("audition_invitation",
#     recipient_name: "John",
#     production_name: "Hamlet"
#   )
#   # => { subject: "...", body: "...", channel: :message, template: ContentTemplate }
#
#   # Render without channel info (backwards compatible)
#   result = ContentTemplateService.render("template_key", variables, strict: true)
#   # => { subject: "...", body: "..." }
#
#   # Deliver via the appropriate channel(s)
#   ContentTemplateService.deliver(
#     template_key: "audition_invitation",
#     variables: { recipient_name: "John", ... },
#     sender: current_user,
#     recipients: [person1, person2],
#     production: production
#   )
#
class ContentTemplateService
  class TemplateNotFoundError < StandardError; end
  class MissingVariablesError < StandardError; end
  class DeliveryError < StandardError; end

  class << self
    # Render a template and return content with channel information
    # @param key [String] The template key
    # @param variables [Hash] Variables to interpolate
    # @param strict [Boolean] If true, raises error for missing variables
    # @return [Hash] { subject: String, body: String, channel: Symbol, template: ContentTemplate }
    def render(key, variables = {}, strict: false)
      template = find_template(key)
      raise TemplateNotFoundError, "Template '#{key}' not found" unless template

      variables = variables.transform_keys(&:to_s)

      if strict
        missing = template.variable_names - variables.keys
        if missing.any?
          raise MissingVariablesError, "Missing variables for template '#{key}': #{missing.join(', ')}"
        end
      end

      {
        subject: template.render_subject(variables),
        body: template.render_body(variables),
        channel: template.channel.to_sym,
        template: template
      }
    end

    # Render a template with channel information included (alias for render)
    # @deprecated Use render instead
    def render_with_channel(key, variables = {})
      render(key, variables)
    end

    # Render only the subject line from a template
    # @param key [String] The template key
    # @param variables [Hash] Variables to interpolate
    # @return [String] The rendered subject
    def render_subject(key, variables = {})
      template = find_template(key)
      raise TemplateNotFoundError, "Template '#{key}' not found" unless template

      template.render_subject(variables.transform_keys(&:to_s))
    end

    # Render only the body from a template
    # @param key [String] The template key
    # @param variables [Hash] Variables to interpolate
    # @return [String] The rendered body
    def render_body(key, variables = {})
      template = find_template(key)
      raise TemplateNotFoundError, "Template '#{key}' not found" unless template

      template.render_body(variables.transform_keys(&:to_s))
    end

    # Check if a template exists
    def exists?(key)
      ContentTemplate.active.exists?(key: key)
    end

    # Get a template by key (returns nil if not found)
    def find_template(key)
      ContentTemplate.active.find_by(key: key)
    end

    # List all available templates
    def all_templates
      ContentTemplate.active.order(:category, :name)
    end

    # List templates by category
    def templates_by_category(category)
      ContentTemplate.active.by_category(category).order(:name)
    end

    # Create or update a template from a hash
    # Useful for seeding templates
    def upsert(key, attributes)
      template = ContentTemplate.find_or_initialize_by(key: key)
      template.assign_attributes(attributes)
      template.save!
      template
    end

    # Render a template for preview with sample data
    def preview(key, sample_variables = nil)
      template = find_template(key)
      raise TemplateNotFoundError, "Template '#{key}' not found" unless template

      # If no sample variables provided, use placeholder values
      variables = sample_variables || generate_sample_variables(template)

      {
        subject: template.render_subject(variables),
        body: template.render_body(variables),
        variables_used: template.variable_names,
        available_variables: template.variables_with_descriptions
      }
    end

    # Get the channel for a template
    # @param key [String] The template key
    # @return [Symbol] :email, :message, or :both
    def channel_for(key)
      template = find_template(key)
      template&.channel&.to_sym || :email
    end

    # Check if template should send a message
    def sends_message?(key)
      channel = channel_for(key)
      channel == :message || channel == :both
    end

    # Check if template should send an email
    def sends_email?(key)
      channel = channel_for(key)
      channel == :email || channel == :both
    end

    # Deliver content via the appropriate channel(s) based on template settings
    #
    # @param template_key [String] The template key
    # @param variables [Hash] Variables to interpolate (can include per-recipient overrides)
    # @param sender [User] The user sending the content
    # @param recipients [Array<Person>] People to receive the content
    # @param production [Production] Optional production context
    # @param show [Show] Optional show context
    # @param organization [Organization] Optional organization context
    # @param message_type [Symbol] Type of message (for MessageService)
    # @param visibility [Symbol] Message visibility (:personal, :production, :show)
    # @param mailer_method [Symbol] For email channel, which mailer method to use
    # @param mailer_class [Class] For email channel, which mailer class to use
    # @param email_batch [EmailBatch] Optional batch for tracking
    #
    # @return [Hash] { messages: [Message], emails_queued: Integer, channel: Symbol }
    def deliver(template_key:, variables:, sender:, recipients:,
                production: nil, show: nil, organization: nil,
                message_type: :system, visibility: :personal,
                mailer_class: nil, mailer_method: nil, email_batch: nil)
      result = render(template_key, variables)
      channel = result[:channel]

      delivery_result = {
        messages: [],
        emails_queued: 0,
        channel: channel
      }

      # Deliver via message channel
      if channel == :message || channel == :both
        message = deliver_as_message(
          subject: result[:subject],
          body: result[:body],
          sender: sender,
          recipients: recipients,
          production: production,
          show: show,
          organization: organization,
          message_type: message_type,
          visibility: visibility
        )
        delivery_result[:messages] << message if message
      end

      # Deliver via email channel
      if channel == :email || channel == :both
        count = deliver_as_email(
          subject: result[:subject],
          body: result[:body],
          recipients: recipients,
          production: production,
          mailer_class: mailer_class,
          mailer_method: mailer_method,
          email_batch: email_batch,
          variables: variables
        )
        delivery_result[:emails_queued] = count
      end

      delivery_result
    end

    # Deliver to multiple recipients with per-recipient variable customization
    #
    # @param template_key [String] The template key
    # @param recipient_variables [Array<Hash>] Array of { person: Person, variables: Hash }
    # @param sender [User] The user sending the content
    # @param production [Production] Optional production context
    # @param ... other options same as deliver
    #
    # @return [Hash] { messages: [Message], emails_queued: Integer }
    def deliver_batch(template_key:, recipient_variables:, sender:,
                      production: nil, show: nil, organization: nil,
                      message_type: :system, visibility: :personal,
                      mailer_class: nil, mailer_method: nil, email_batch: nil)
      template = find_template(template_key)
      raise TemplateNotFoundError, "Template '#{template_key}' not found" unless template

      channel = template.channel.to_sym

      delivery_result = {
        messages: [],
        emails_queued: 0,
        channel: channel
      }

      # For messages, we create one message with all recipients
      # (MessageService handles the multi-recipient case)
      if channel == :message || channel == :both
        # Use first recipient's variables for the shared message
        # (In practice, batch messages often have same content)
        first_vars = recipient_variables.first&.dig(:variables) || {}
        rendered = render(template_key, first_vars)

        people = recipient_variables.map { |rv| rv[:person] }.compact

        message = deliver_as_message(
          subject: rendered[:subject],
          body: rendered[:body],
          sender: sender,
          recipients: people,
          production: production,
          show: show,
          organization: organization,
          message_type: message_type,
          visibility: visibility
        )
        delivery_result[:messages] << message if message
      end

      # For emails, we send individually with per-recipient customization
      if channel == :email || channel == :both
        recipient_variables.each do |rv|
          person = rv[:person]
          vars = rv[:variables] || {}
          rendered = render(template_key, vars)

          count = deliver_as_email(
            subject: rendered[:subject],
            body: rendered[:body],
            recipients: [ person ],
            production: production,
            mailer_class: mailer_class,
            mailer_method: mailer_method,
            email_batch: email_batch,
            variables: vars
          )
          delivery_result[:emails_queued] += count
        end
      end

      delivery_result
    end

    private

    # Generate placeholder sample values for variables
    def generate_sample_variables(template)
      template.variables_with_descriptions.each_with_object({}) do |var, hash|
        name = var[:name].to_s
        hash[name] = sample_value_for(name, template.key)
      end
    end

    # Generate a sample value based on variable name
    def sample_value_for(name, template_key = nil)
      case name
      when /email/i then "example@email.com"
      when /production_name|production_title/i then "Singin' in the Rain"
      when /show_name|show_title/i then "Opening Night - Singin' in the Rain"
      when /group_name/i then "The Riverside Players"
      when /organization_name/i then "Downtown Arts Center"
      when /role_name/i then "Don Lockwood"
      when /recipient_name|inviter_name|sender_name|author_name|talent_name/i then "Sarah Johnson"
      when /requester_name|vacated_by_name|filled_by_name/i then "Michael Chen"
      when /name/i then "Alex Thompson"
      when /title/i then "Example Title"
      when /show_info/i then "Saturday, March 15, 2025 at 7:30 PM - Main Stage"
      when /show_date/i then "Saturday, March 15, 2025"
      when /date/i then Date.current.strftime("%B %d, %Y")
      when /time/i then "7:30 PM"
      when /url|link/i then "https://cocoscout.com/example-link"
      when /custom_message/i then "<p>Looking forward to having you join our production!</p>"
      when /body_content/i then sample_body_content(template_key)
      when /shoutout_content/i then "Amazing performance last night! The whole cast was incredible."
      when /subject/i then sample_subject(template_key)
      when /count|number/i then "5"
      else "[#{name}]"
      end
    end

    # Generate realistic sample body content based on template type
    def sample_body_content(template_key)
      case template_key.to_s
      when "audition_invitation"
        <<~HTML
          <p>We're holding auditions for our upcoming production and would love for you to audition!</p>
          <p><strong>Audition Details:</strong></p>
          <ul>
            <li>Date: Saturday, March 15, 2025</li>
            <li>Time: 10:00 AM - 4:00 PM</li>
            <li>Location: Downtown Arts Center, Main Stage</li>
          </ul>
          <p>Please prepare a 1-2 minute monologue and be ready to do a cold reading from the script.</p>
          <p><a href="https://cocoscout.com/audition-link">Click here to sign up for an audition slot</a></p>
        HTML
      when "cast_notification", "casting_email"
        <<~HTML
          <p>Congratulations! You have been cast in our upcoming production of <strong>Singin' in the Rain</strong>!</p>
          <p>You will be playing the role of <strong>Don Lockwood</strong>.</p>
          <p><strong>Rehearsal Schedule:</strong></p>
          <ul>
            <li>First read-through: Monday, April 1st at 7:00 PM</li>
            <li>Regular rehearsals: Tues/Thurs 7-10 PM, Saturdays 10 AM-2 PM</li>
            <li>Tech Week: June 9-13</li>
            <li>Performances: June 14-22</li>
          </ul>
          <p>Please confirm your acceptance by clicking the link below:</p>
          <p><a href="https://cocoscout.com/confirm-cast">Confirm Your Role</a></p>
        HTML
      when "contact_message"
        <<~HTML
          <p>Hi Sarah,</p>
          <p>I saw your profile on CocoScout and I think you'd be perfect for an upcoming project we're casting. It's a new musical adaptation and we're looking for strong singers who can also move well.</p>
          <p>Would you be interested in coming in for an audition? We're seeing people next week at the Downtown Arts Center.</p>
          <p>Let me know and I can send you more details!</p>
        HTML
      when "removed_from_cast_notification"
        <<~HTML
          <p>We regret to inform you that your role in <strong>Singin' in the Rain</strong> has been recast.</p>
          <p>We understand this is disappointing news. If you have any questions, please don't hesitate to reach out to the production team.</p>
          <p>We hope to work with you on future productions.</p>
        HTML
      when "vacancy_invitation", "vacancy_created"
        <<~HTML
          <p>A role has become available in <strong>Singin' in the Rain</strong> and we think you'd be a great fit!</p>
          <p><strong>Role:</strong> Cosmo Brown (Lead)</p>
          <p><strong>Show Dates:</strong> June 14-22, 2025</p>
          <p>This is a paid position. If you're interested and available, please respond as soon as possible.</p>
          <p><a href="https://cocoscout.com/vacancy-link">View Details & Respond</a></p>
        HTML
      when "availability_request_person", "availability_request_group"
        <<~HTML
          <p>We're planning our upcoming production schedule and need to check your availability.</p>
          <p>Please let us know your availability for the following dates:</p>
          <ul>
            <li>Rehearsals: April 1 - June 13 (Tues/Thurs evenings, Saturday mornings)</li>
            <li>Tech Week: June 9-13 (full days required)</li>
            <li>Performances: June 14-22</li>
          </ul>
          <p><a href="https://cocoscout.com/availability-link">Submit Your Availability</a></p>
        HTML
      when "questionnaire_invitation"
        <<~HTML
          <p>As part of your involvement in <strong>Singin' in the Rain</strong>, we need you to complete a brief questionnaire.</p>
          <p>This helps us with costume fittings, program bios, and other production logistics.</p>
          <p><a href="https://cocoscout.com/questionnaire-link">Complete the Questionnaire</a></p>
          <p>Please complete this by Friday, March 21st.</p>
        HTML
      else
        <<~HTML
          <p>We're excited to share some news with you about our upcoming production.</p>
          <p>Please click the link below for more details:</p>
          <p><a href="https://cocoscout.com/details">View Details</a></p>
        HTML
      end.strip
    end

    # Generate realistic sample subject based on template type
    def sample_subject(template_key)
      case template_key.to_s
      when "cast_notification" then "You've been cast in Singin' in the Rain!"
      when "casting_email" then "Casting Update for Singin' in the Rain"
      when "contact_message" then "Audition Opportunity - New Musical"
      when "removed_from_cast_notification" then "Update Regarding Your Role in Singin' in the Rain"
      else "Message from The Riverside Players"
      end
    end

    def deliver_as_message(subject:, body:, sender:, recipients:,
                           production:, show:, organization:, message_type:, visibility:)
      # Filter to people with user accounts
      valid_recipients = Array(recipients).select { |p| p.is_a?(Person) && p.user.present? }
      return nil if valid_recipients.empty?

      MessageService.create_message(
        sender: sender,
        recipients: valid_recipients,
        subject: subject,
        body: body,
        production: production,
        show: show,
        organization: organization || production&.organization,
        message_type: message_type,
        visibility: visibility
      )
    end

    def deliver_as_email(subject:, body:, recipients:, production:,
                         mailer_class:, mailer_method:, email_batch:, variables:)
      count = 0
      Array(recipients).each do |person|
        next unless person.respond_to?(:email) && person.email.present?

        if mailer_class && mailer_method
          # Use the specified mailer
          mailer_class.send(mailer_method, person, production, body, subject,
                            email_batch_id: email_batch&.id).deliver_later
        else
          # Fall back to a generic notification mailer if available
          Rails.logger.warn "ContentTemplateService: No mailer specified for email delivery to #{person.email}"
        end
        count += 1
      end
      count
    end
  end
end
