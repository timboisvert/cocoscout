# frozen_string_literal: true

class EmailTemplate < ApplicationRecord
  validates :key, presence: true, uniqueness: true
  validates :name, presence: true
  validates :subject, presence: true
  validates :body, presence: true

  scope :active, -> { where(active: true) }
  scope :by_category, ->(category) { where(category: category) }

  # Categories for organizing templates
  CATEGORIES = %w[
    invitation
    notification
    reminder
    confirmation
    marketing
    system
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

  # Returns the list of variable names used in the template
  def variable_names
    (extract_variables(subject) + extract_variables(body)).uniq
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
