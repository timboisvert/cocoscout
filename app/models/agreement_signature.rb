# frozen_string_literal: true

# AgreementSignature records when a performer signs a production's agreement.
#
# Critical fields for legal compliance:
# - content_snapshot: Exact content they agreed to (in case template changes later)
# - signed_at: Timestamp of signature
# - ip_address: For audit trail
# - user_agent: Browser/device info for audit trail
#
class AgreementSignature < ApplicationRecord
  belongs_to :person
  belongs_to :production
  belongs_to :agreement_template, optional: true

  validates :signed_at, presence: true
  validates :content_snapshot, presence: true
  validates :person_id, uniqueness: { scope: :production_id, message: "has already signed this agreement" }

  scope :recent, -> { order(signed_at: :desc) }
  scope :for_production, ->(production) { where(production: production) }

  # Create a signature with all required audit info
  def self.sign!(person:, production:, request:)
    template = production.agreement_template
    content = production.rendered_agreement_content(person)

    create!(
      person: person,
      production: production,
      agreement_template: template,
      signed_at: Time.current,
      ip_address: request.remote_ip,
      user_agent: request.user_agent&.truncate(500),
      content_snapshot: content,
      template_version: template&.version
    )
  end

  # Format signed_at for display
  def signed_on
    signed_at.strftime("%B %-d, %Y")
  end
end
