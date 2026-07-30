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
    "current_date"        => "Today's date",
    "license_schedule"    => "The dates/stage/rent grid — drop it inside a section to place the schedule inline (otherwise the Deal Terms schedule is appended automatically)",
    "services"            => "The service line items on the deal (name, quantity, rate) — renders nothing if the contract has no services"
  }.freeze

  # A representative dates/stage/rent grid for the editor preview. The real one is
  # generated per contract from its bookings (Contract#license_schedule_html); this
  # stand-in just shows the author what {{license_schedule}} will become.
  SAMPLE_LICENSE_SCHEDULE = <<~HTML.strip
    <table><thead><tr><th>Dates</th><th>Event</th><th>Start</th><th>End</th><th>Stage</th><th>Rent</th></tr></thead><tbody>
    <tr><td>Fri Mar 6, 2026</td><td>Example Production</td><td>8:00 PM</td><td>10:00 PM</td><td>The Mainstage</td><td>$500.00</td></tr>
    <tr><td>Sat Mar 7, 2026</td><td>Example Production</td><td>8:00 PM</td><td>10:00 PM</td><td>The Mainstage</td><td>$500.00</td></tr>
    </tbody></table>
    <h4>Payment schedule</h4><table><thead><tr><th>Payment</th><th>Amount</th><th>Due</th></tr></thead><tbody>
    <tr><td>Deposit</td><td>$500.00</td><td>Feb 6, 2026</td></tr>
    <tr><td>Balance</td><td>$500.00</td><td>Mar 6, 2026</td></tr>
    </tbody></table>
  HTML

  # A representative services list for the editor preview, standing in for the
  # per-contract {{services}} token (Contract#license_services_html).
  SAMPLE_SERVICES = <<~HTML.strip
    <h4>Services</h4><ul>
    <li>Sound technician × 2 — $25.00/hr</li>
    <li>Stagehand — $20.00/hr</li>
    </ul>
  HTML

  # Render content with {{variable}} substitution (same approach as AgreementTemplate).
  def render_content(variables = {})
    return "" unless content.present?

    rendered = content.body.to_html
    variables.each do |key, value|
      rendered = rendered.gsub("{{#{key}}}", ERB::Util.html_escape(value.to_s))
    end
    rendered.html_safe
  end

  # Render for the editor's "Preview with sample data": merge fields filled from
  # the given sample values, and the inline {{license_schedule}} / {{services}}
  # tokens replaced with representative sample grids (the real ones are generated
  # per contract in Contract, so the template can't produce them on its own).
  def render_preview(variables = {})
    render_content(variables)
      .to_s
      .gsub(Contract::LICENSE_SCHEDULE_TOKEN, SAMPLE_LICENSE_SCHEDULE)
      .gsub(Contract::SERVICES_TOKEN, SAMPLE_SERVICES)
      .html_safe
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
