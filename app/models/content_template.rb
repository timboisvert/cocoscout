# frozen_string_literal: true

# ContentTemplate stores reusable templates for messages and emails.
#
# Templates can be delivered via different channels:
# - :email - Send via email only (default for auth, invitations to non-users)
# - :message - Create in-app message only
# - :both - Create message AND send email notification
#
# Formerly EmailTemplate - renamed to reflect that templates now support
# both email and in-app messaging channels.
#
class ContentTemplate < ApplicationRecord
  validates :key, presence: true, uniqueness: true
  validates :name, presence: true
  validates :subject, presence: true
  validates :body, presence: true

  scope :active, -> { where(active: true) }
  scope :by_category, ->(category) { where(category: category) }

  # Channel determines delivery method
  # - email: Send via email only (default for auth, invitations to non-users)
  # - message: Create in-app message only
  # - both: Create message AND send email notification
  enum :channel, {
    email: "email",
    message: "message",
    both: "both"
  }, default: :email

  # Categories for organizing templates by site section
  CATEGORIES = %w[
    auth
    profiles
    casting
    signups
    shows
    payments
    messages
  ].freeze

  # Template types - describes how the template is used in the app
  TEMPLATE_TYPES = {
    "structured" => "Structured template with fixed layout and variable placeholders",
    "passthrough" => "Content is passed through from user input (e.g., contact forms)",
    "hybrid" => "Template provides default content but user can customize before sending"
  }.freeze

  # Returns a human-readable description of the template type
  def template_type_description
    TEMPLATE_TYPES[template_type] || "Unknown type"
  end

  # Check if this template's content comes from user input
  def passthrough?
    template_type == "passthrough"
  end

  # Check if user can customize before sending
  def hybrid?
    template_type == "hybrid"
  end

  # Check if template has fixed structure
  def structured?
    template_type == "structured" || template_type.blank?
  end

  # Render the subject with variable substitution
  def render_subject(variables = {})
    interpolate(subject, variables)
  end

  # Render the body with variable substitution
  def render_body(variables = {})
    interpolate(body, variables)
  end

  # Render the message body with variable substitution
  # For "both" channel templates, uses message_body if present, otherwise falls back to body
  # For message-only templates, uses body
  def render_message_body(variables = {})
    content = if both? && message_body.present?
                message_body
    else
                body
    end
    interpolate(content, variables)
  end

  # Returns the list of variable names used in the template
  def variable_names
    texts = [ subject, body ]
    texts << message_body if both? && message_body.present?
    texts.compact.flat_map { |t| extract_variables(t) }.uniq
  end

  # Returns available variables with their descriptions
  def variables_with_descriptions
    return [] if available_variables.blank?

    available_variables.map do |var|
      if var.is_a?(Hash)
        var.symbolize_keys
      else
        { name: var.to_s, description: nil }
      end
    end
  end

  private

  # Interpolate variables in the format {{variable_name}}
  # Also handles mustache-style conditionals: {{#var}}content{{/var}}
  def interpolate(text, variables)
    return text if text.blank?

    result = text.dup

    # First handle conditional blocks: {{#var}}content{{/var}}
    # If the variable is present and not blank, show the content; otherwise remove the block
    variables.each do |key, value|
      # Match {{#key}}...{{/key}} blocks
      result.gsub!(/\{\{##{Regexp.escape(key.to_s)}\}\}(.+?)\{\{\/#{Regexp.escape(key.to_s)}\}\}/m) do |_match|
        value.present? ? $1 : ""
      end
    end

    # Remove any remaining conditional blocks for variables not provided
    result.gsub!(/\{\{#\w+\}\}.+?\{\{\/\w+\}\}/m, "")

    # Then handle simple variable substitution
    variables.each do |key, value|
      result.gsub!(/\{\{\s*#{Regexp.escape(key.to_s)}\s*\}\}/, value.to_s)
    end
    result
  end

  # Extract variable names from text (looks for {{variable_name}})
  def extract_variables(text)
    return [] if text.blank?

    text.scan(/\{\{\s*(\w+)\s*\}\}/).flatten.uniq
  end
end
