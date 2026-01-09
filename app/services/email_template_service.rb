# frozen_string_literal: true

# Service for rendering email templates with variable interpolation.
#
# Usage:
#   EmailTemplateService.render("invitation_to_audition",
#     recipient_name: "John",
#     production_title: "Hamlet",
#     role_name: "Hamlet"
#   )
#
# Returns:
#   { subject: "You're invited to audition for Hamlet", body: "Dear John, ..." }
#
class EmailTemplateService
  class TemplateNotFoundError < StandardError; end
  class MissingVariablesError < StandardError; end

  class << self
    # Render a template by key with the given variables
    # @param key [String] The template key
    # @param variables [Hash] Variables to interpolate
    # @param strict [Boolean] If true, raises error for missing variables
    # @return [Hash] { subject: String, body: String }
    def render(key, variables = {}, strict: false)
      template = find_template(key)
      raise TemplateNotFoundError, "Email template '#{key}' not found" unless template

      variables = variables.transform_keys(&:to_s)

      if strict
        missing = template.variable_names - variables.keys
        if missing.any?
          raise MissingVariablesError, "Missing variables for template '#{key}': #{missing.join(', ')}"
        end
      end

      {
        subject: template.render_subject(variables),
        body: template.render_body(variables)
      }
    end

    # Render only the subject line from a template
    # @param key [String] The template key
    # @param variables [Hash] Variables to interpolate
    # @return [String] The rendered subject
    def render_subject(key, variables = {})
      template = find_template(key)
      raise TemplateNotFoundError, "Email template '#{key}' not found" unless template

      template.render_subject(variables.transform_keys(&:to_s))
    end

    # Render subject WITHOUT production name prefix (for UI forms where prefix is shown separately)
    # @param key [String] The template key
    # @param variables [Hash] Variables to interpolate
    # @return [String] The rendered subject without prefix
    def render_subject_without_prefix(key, variables = {})
      template = find_template(key)
      raise TemplateNotFoundError, "Email template '#{key}' not found" unless template

      template.render_subject_without_prefix(variables.transform_keys(&:to_s))
    end

    # Render only the body from a template
    # @param key [String] The template key
    # @param variables [Hash] Variables to interpolate
    # @return [String] The rendered body
    def render_body(key, variables = {})
      template = find_template(key)
      raise TemplateNotFoundError, "Email template '#{key}' not found" unless template

      template.render_body(variables.transform_keys(&:to_s))
    end

    # Check if a template exists
    def exists?(key)
      EmailTemplate.active.exists?(key: key)
    end

    # Get a template by key (returns nil if not found)
    def find_template(key)
      EmailTemplate.active.find_by(key: key)
    end

    # List all available templates
    def all_templates
      EmailTemplate.active.order(:category, :name)
    end

    # List templates by category
    def templates_by_category(category)
      EmailTemplate.active.by_category(category).order(:name)
    end

    # Create or update a template from a hash
    # Useful for seeding templates
    def upsert(key, attributes)
      template = EmailTemplate.find_or_initialize_by(key: key)
      template.assign_attributes(attributes)
      template.save!
      template
    end

    # Render a template for preview with sample data
    def preview(key, sample_variables = nil)
      template = find_template(key)
      raise TemplateNotFoundError, "Email template '#{key}' not found" unless template

      # If no sample variables provided, use placeholder values
      variables = sample_variables || generate_sample_variables(template)

      {
        subject: template.render_subject(variables),
        body: template.render_body(variables),
        variables_used: template.variable_names,
        available_variables: template.variables_with_descriptions
      }
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
  end
end
