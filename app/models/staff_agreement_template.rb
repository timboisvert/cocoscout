# frozen_string_literal: true

# StaffAgreementTemplate is a reusable employee/staff agreement (the terms a staff
# member agrees to when they onboard), mirroring ContractTemplate. Organizations
# keep one or more named agreements with {{merge_fields}} that get filled from a
# staff member's data when they're shown the agreement during onboarding.
#
# Templates are versioned — when content changes, the version increments — so the
# exact wording a staff member agreed to is traceable even if the template changes.
class StaffAgreementTemplate < ApplicationRecord
  include StaffAgreementTemplateDefaults

  belongs_to :organization
  has_many :organization_staff_members, dependent: :nullify

  has_rich_text :content

  validates :name, presence: true
  validate :content_present
  validates :version, presence: true, numericality: { greater_than: 0 }

  scope :active, -> { where(active: true) }
  scope :for_organization, ->(org) { where(organization: org) }

  before_save :increment_version_on_content_change
  before_destroy :clear_org_required_pointer

  # The merge fields a staff agreement may reference, with a human label. Drives
  # the "Available Variables" helper in the editor and the preview's sample data.
  MERGE_FIELDS = {
    "staff_name"        => "The staff member's name",
    "organization_name" => "Your organization name",
    "title"             => "The staff member's job title",
    "department"        => "The staff member's department",
    "start_date"        => "The staff member's start date",
    "current_date"      => "Today's date"
  }.freeze

  # Render content with {{variable}} substitution (same approach as ContractTemplate).
  def render_content(variables = {})
    return "" unless content.present?

    rendered = content.body.to_html
    variables.each do |key, value|
      rendered = rendered.gsub("{{#{key}}}", ERB::Util.html_escape(value.to_s))
    end
    rendered.html_safe
  end

  # Is this the agreement the org currently requires staff to sign?
  def required_for_org?
    organization.required_staff_agreement_template_id == id
  end

  # Active staff this agreement covers, for the roster view. For the org's REQUIRED
  # agreement that's everyone on staff (they all must sign); for any other template
  # it's whoever has actually signed this specific one.
  def applicable_staff_members
    scope = required_for_org? ? organization.organization_staff_members : organization_staff_members
    scope.active.includes(:person).to_a
  end

  # Signature tally for the required agreement: still-owed vs signed-current vs
  # exempt. `pending` is what matters most — who still has to sign. Only meaningful
  # when required_for_org? (otherwise pending is 0).
  def signing_summary
    members = applicable_staff_members
    {
      total:   members.size,
      signed:  members.count(&:signed_required_agreement?),
      pending: members.count(&:needs_to_sign_agreement?),
      exempt:  members.count(&:agreement_exempt?)
    }
  end

  private

  def increment_version_on_content_change
    return unless content.changed? && persisted?

    self.version += 1
  end

  def content_present
    errors.add(:content, "can't be blank") if content.blank?
  end

  # If this template was the org's required agreement, clear that pointer so we
  # never leave a dangling requirement pointing at a destroyed template.
  def clear_org_required_pointer
    return unless organization&.required_staff_agreement_template_id == id

    organization.update_column(:required_staff_agreement_template_id, nil)
  end
end
