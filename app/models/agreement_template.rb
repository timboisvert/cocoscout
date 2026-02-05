# frozen_string_literal: true

# AgreementTemplate represents a reusable performer agreement document.
#
# Organizations create templates for different types of productions
# (e.g., "Burlesque Agreement", "Comedy Agreement") with their own
# payment structures and terms.
#
# Templates are versioned - when content changes, the version increments.
# Signatures always snapshot the exact content signed.
#
class AgreementTemplate < ApplicationRecord
  belongs_to :organization
  has_many :productions, dependent: :nullify
  has_many :agreement_signatures, dependent: :restrict_with_error

  has_rich_text :content

  validates :name, presence: true
  validate :content_present
  validates :version, presence: true, numericality: { greater_than: 0 }

  scope :active, -> { where(active: true) }
  scope :for_organization, ->(org) { where(organization: org) }

  # Increment version when content changes
  before_save :increment_version_on_content_change

  # Render content with variable substitution
  # Variables: {{production_name}}, {{organization_name}}, {{performer_name}}, {{current_date}}
  def render_content(variables = {})
    return "" unless content.present?

    rendered = content.body.to_html # Get raw HTML without ActionText wrapper
    variables.each do |key, value|
      rendered.gsub!("{{#{key}}}", ERB::Util.html_escape(value.to_s))
    end
    rendered.html_safe
  end

  # Count of signatures across all productions using this template
  def total_signatures
    agreement_signatures.count
  end

  # Productions currently using this template
  def active_productions
    productions.where.not(archived_at: nil)
  end

  private

  def increment_version_on_content_change
    return unless content.changed? && persisted?

    self.version += 1
  end

  def content_present
    errors.add(:content, "can't be blank") if content.blank?
  end
end
