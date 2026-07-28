# frozen_string_literal: true

# ContractTemplate is a reusable contract document (the legal wording behind a
# deal), mirroring AgreementTemplate. Organizations keep a few named templates
# ("Rental Agreement", "Performer Deal") with {{merge_fields}} that get filled
# from a contract's data when it's sent for signature.
#
# Templates are versioned — when content changes, the version increments — so a
# signature can snapshot the exact content signed even if the template changes.
class ContractTemplate < ApplicationRecord
  belongs_to :organization
  has_many :contracts, dependent: :nullify

  has_rich_text :content

  validates :name, presence: true
  validate :content_present
  validates :version, presence: true, numericality: { greater_than: 0 }

  scope :active, -> { where(active: true) }
  scope :for_organization, ->(org) { where(organization: org) }

  before_save :increment_version_on_content_change

  # The merge fields a contract template may reference, with a human label. Drives
  # the "Available Variables" helper in the editor and the preview's sample data.
  MERGE_FIELDS = {
    "contractor_name"     => "The contractor / counterparty name",
    "organization_name"   => "Your organization name",
    "production_name"     => "The production / show name",
    "contract_start_date" => "Contract start date",
    "contract_end_date"   => "Contract end date",
    "current_date"        => "Today's date"
  }.freeze

  # Render content with {{variable}} substitution (same approach as AgreementTemplate).
  def render_content(variables = {})
    return "" unless content.present?

    rendered = content.body.to_html
    variables.each do |key, value|
      rendered = rendered.gsub("{{#{key}}}", ERB::Util.html_escape(value.to_s))
    end
    rendered.html_safe
  end

  def total_contracts
    contracts.count
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
