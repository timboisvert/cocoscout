# frozen_string_literal: true

# One signed Form W-9 a person gave an organization (the payer). Either
# collected electronically on the staff member's W-9 page (source "online"),
# or one the org already had — signed on paper or through another system —
# uploaded by a manager with the fields a 1099 needs typed in ("uploaded").
# History is kept: a new W-9 of either kind supersedes the old one, and the
# newest un-superseded row is current.
#
# The TIN (SSN or EIN) is encrypted at rest. Screens only ever show
# `masked_tin`; the full number appears only in the on-demand W-9 PDF, or in
# the uploaded file, which is only ever streamed through the Taxes controller
# (and logged), never linked.
class W9Submission < ApplicationRecord
  # The IRS revision of Form W-9 this substitute form follows.
  FORM_REVISION = "2024-03"

  # Line 3a, federal tax classification.
  TAX_CLASSIFICATIONS = {
    "individual" => "Individual/sole proprietor",
    "c_corporation" => "C corporation",
    "s_corporation" => "S corporation",
    "partnership" => "Partnership",
    "trust_estate" => "Trust/estate",
    "llc" => "LLC",
    "other" => "Other"
  }.freeze
  # For an LLC: how it's taxed (C, S, or P).
  LLC_TAX_CLASSES = { "C" => "C corporation", "S" => "S corporation", "P" => "Partnership" }.freeze
  TIN_TYPES = %w[ssn ein].freeze
  SOURCES = %w[online uploaded].freeze
  # What an uploaded W-9 may be: a PDF or a photo of the paper form.
  DOCUMENT_TYPES = %w[application/pdf image/jpeg image/png].freeze
  DOCUMENT_MAX_BYTES = 10.megabytes

  US_STATES = %w[
    AL AK AZ AR CA CO CT DE DC FL GA HI ID IL IN IA KS KY LA ME MD MA MI MN MS MO MT NE NV NH NJ NM NY
    NC ND OH OK OR PA RI SC SD TN TX UT VT VA WA WV WI WY AS GU MP PR VI
  ].freeze

  # The Part II certification, word for word from the IRS form. It's what the
  # contractor signs, and it's printed on the PDF.
  CERTIFICATION_ITEMS = [
    "The number shown on this form is my correct taxpayer identification number (or I am waiting for a number to be issued to me); and",
    "I am not subject to backup withholding because (a) I am exempt from backup withholding, or (b) I have not been notified by the Internal Revenue Service (IRS) that I am subject to backup withholding as a result of a failure to report all interest or dividends, or (c) the IRS has notified me that I am no longer subject to backup withholding; and",
    "I am a U.S. citizen or other U.S. person (defined in the instructions); and",
    "The FATCA code(s) entered on this form (if any) indicating that I am exempt from FATCA reporting is correct."
  ].freeze
  CERTIFICATION_INTRO = "Under penalties of perjury, I certify that:"

  belongs_to :organization
  belongs_to :person
  belongs_to :organization_staff_member, optional: true
  belongs_to :uploaded_by, class_name: "User", optional: true
  has_many :tax_document_accesses, dependent: :destroy
  has_one_attached :document

  encrypts :tin

  scope :current, -> { where(superseded_at: nil) }

  before_validation :normalize

  validates :source, inclusion: { in: SOURCES }
  validates :legal_name, :address_line1, :city, presence: true
  # Signed online, in their own words; an upload was signed on the paper form.
  validates :signature_name, presence: true, unless: :uploaded?
  validate :document_attached_and_sane, if: :uploaded?
  validates :tax_classification, inclusion: { in: TAX_CLASSIFICATIONS.keys }
  validates :llc_tax_class, inclusion: { in: LLC_TAX_CLASSES.keys, message: "is required for an LLC" }, if: -> { tax_classification == "llc" }
  validates :other_classification, presence: true, if: -> { tax_classification == "other" }
  validates :tin_type, inclusion: { in: TIN_TYPES }
  validates :tin, format: { with: /\A\d{9}\z/, message: "must be 9 digits" }
  validates :state, inclusion: { in: US_STATES, message: "must be a US state" }
  validates :zip, format: { with: /\A\d{5}(-\d{4})?\z/, message: "must be a 5-digit ZIP code" }
  validates :signed_at, :form_revision, presence: true

  # Save this W-9 as the person's current one with the org, retiring any older
  # one in the same transaction (only one current W-9 per person per org).
  def submit!
    transaction do
      self.class.current.where(organization_id: organization_id, person_id: person_id)
          .where.not(id: id).update_all(superseded_at: Time.current, updated_at: Time.current)
      save!
    end
  end

  def uploaded?
    source == "uploaded"
  end

  def masked_tin
    tin_type == "ein" ? "••-•••#{tin_last4}" : "•••-••-#{tin_last4}"
  end

  # The full TIN, formatted the way the form prints it.
  def formatted_tin
    return "" if tin.blank?

    tin_type == "ein" ? "#{tin[0, 2]}-#{tin[2..]}" : "#{tin[0, 3]}-#{tin[3, 2]}-#{tin[5..]}"
  end

  def classification_label
    label = TAX_CLASSIFICATIONS[tax_classification]
    case tax_classification
    when "llc" then "#{label} (taxed as #{LLC_TAX_CLASSES[llc_tax_class]})"
    when "other" then "#{label}: #{other_classification}"
    else label
    end
  end

  def e_delivery_consented?
    e_delivery_consented_at.present?
  end

  def city_state_zip
    "#{city}, #{state} #{zip}"
  end

  private

  def document_attached_and_sane
    unless document.attached?
      errors.add(:document, "is required — attach the W-9 you have")
      return
    end
    errors.add(:document, "must be a PDF, JPG or PNG") unless DOCUMENT_TYPES.include?(document.blob.content_type)
    errors.add(:document, "must be 10 MB or smaller") if document.blob.byte_size.to_i > DOCUMENT_MAX_BYTES
  end

  def normalize
    digits = tin.to_s.gsub(/\D/, "")
    self.tin = digits
    self.tin_last4 = digits.last(4)
    self.state = state.to_s.strip.upcase
    self.zip = zip.to_s.strip
    self.llc_tax_class = nil unless tax_classification == "llc"
    self.other_classification = nil unless tax_classification == "other"
    self.form_revision ||= FORM_REVISION
    %i[legal_name business_name address_line1 address_line2 city signature_name exempt_payee_code fatca_code].each do |attr|
      self[attr] = self[attr].to_s.strip.presence
    end
  end
end
