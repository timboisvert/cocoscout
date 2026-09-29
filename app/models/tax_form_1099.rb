# frozen_string_literal: true

# A Form 1099-NEC an organization will send one of its contractors for a
# given tax year. Generated as a draft (year's earnings + snapshot of the
# person's W-9 + snapshot of the org's payer info), reviewed by the payer,
# marked delivered when the recipient copy goes out, and marked filed by hand
# after the manager uploads the IRS IRIS file (Phase 3 will file for you).
class TaxForm1099 < ApplicationRecord
  self.table_name = "tax_form_1099s"

  # draft      → generated, editable
  # ready      → payer confirmed the numbers look right; recipient copy queued
  # delivered  → recipient copy sent (email or paper)
  # filed      → sent to the IRS (manually recorded)
  # corrected  → a newer form supersedes this one (see corrects_id)
  # void       → cancelled before delivery
  STATUSES = %w[draft ready delivered filed corrected void].freeze
  EDITABLE_STATUSES = %w[draft ready].freeze

  belongs_to :organization
  belongs_to :person
  belongs_to :w9_submission, optional: true
  belongs_to :corrects, class_name: "TaxForm1099", optional: true
  belongs_to :generated_by, class_name: "User", optional: true
  has_many :corrections, class_name: "TaxForm1099", foreign_key: :corrects_id, dependent: :nullify

  validates :tax_year, numericality: { greater_than: 2020, less_than: 2100 }
  validates :status, inclusion: { in: STATUSES }
  validates :nec_box1_cents, :federal_withheld_cents, :adjustment_cents,
            numericality: { only_integer: true }

  scope :for_year, ->(year) { where(tax_year: year) }
  scope :current, -> { where(status: %w[draft ready delivered filed]) }
  scope :not_void, -> { where.not(status: %w[void corrected]) }

  # Payment thresholds for reporting on the 1099-NEC. Legal changes: $600 for
  # payments made through 2025, $2,000 for payments made 2026 and later,
  # indexed for inflation starting 2027 (put this here so a future indexed
  # number is a one-line change).
  NEC_THRESHOLDS = { 2024 => 600_00, 2025 => 600_00, 2026 => 2_000_00 }.freeze

  def self.threshold_cents(year)
    NEC_THRESHOLDS[year] || NEC_THRESHOLDS[NEC_THRESHOLDS.keys.max]
  end

  # Line 1 amount actually reported to the IRS: computed earnings + payer's
  # optional adjustment (money settled outside CocoScout the manager wants to
  # add or remove). Rounded to the nearest dollar on the box, but stored as cents.
  def reported_box1_cents
    nec_box1_cents + adjustment_cents
  end

  def under_threshold?
    reported_box1_cents < self.class.threshold_cents(tax_year)
  end

  def editable?
    EDITABLE_STATUSES.include?(status)
  end

  def masked_recipient_tin
    prefix = recipient_tin_type == "ein" ? "••-•••" : "•••-••-"
    "#{prefix}#{recipient_tin_last4}"
  end

  def masked_payer_ein
    "••-•••#{payer_ein_last4}"
  end

  def recipient_address_lines
    [ recipient_address_line1, recipient_address_line2 ].compact_blank + [ "#{recipient_city}, #{recipient_state} #{recipient_zip}" ]
  end

  def payer_address_lines
    [ payer_address_line1, payer_address_line2 ].compact_blank + [ "#{payer_city}, #{payer_state} #{payer_zip}" ]
  end

  # Build a set of drafts for a tax year from computed earnings. Idempotent —
  # a member who already has a form for the year keeps that form (its amount
  # is refreshed IF the form is still editable). Corrected/void/delivered/filed
  # forms are left alone: a correction is a new form.
  def self.generate_for_year!(organization:, tax_year:, generated_by: nil)
    payer = organization.tax_setting
    raise ArgumentError, "add your payer details before generating 1099s" unless payer&.complete?

    earnings = Tax::YearEarnings.for(organization, tax_year)
    members = organization.organization_staff_members.where(person_id: earnings.keys)
                          .includes(:person, :w9_submissions)

    generated = []
    members.each do |member|
      result = earnings[member.person_id]
      next if result.nil? || result.net_cents <= 0

      form = organization.tax_form_1099s.find_or_initialize_by(person_id: member.person_id, tax_year: tax_year, corrects_id: nil)
      form.nec_box1_cents = result.net_cents
      form.generated_by ||= generated_by

      if form.new_record?
        snapshot_recipient_from(form, member)
        snapshot_payer_from(form, payer)
        form.status = "draft"
        form.save!
        generated << form
      elsif form.editable?
        # Refresh amount and W-9 snapshot for drafts still being tuned; leave
        # anything delivered/filed frozen.
        snapshot_recipient_from(form, member) if member.current_w9&.id != form.w9_submission_id
        form.save! if form.changed?
        generated << form
      end
    end
    generated
  end

  def self.snapshot_recipient_from(form, member)
    w9 = member.current_w9
    if w9
      form.assign_attributes(
        w9_submission: w9,
        recipient_name: w9.legal_name,
        recipient_business_name: w9.business_name,
        recipient_tin_type: w9.tin_type,
        recipient_tin_last4: w9.tin_last4,
        recipient_address_line1: w9.address_line1,
        recipient_address_line2: w9.address_line2,
        recipient_city: w9.city,
        recipient_state: w9.state,
        recipient_zip: w9.zip,
        recipient_e_delivery_consented: w9.e_delivery_consented?
      )
    else
      # No W-9 on file: still generate the draft so it shows up on the Taxes
      # page as blocked. TIN last four is zeroed; the form can't be sent this
      # way, but the payer will see it needs a W-9.
      form.assign_attributes(
        w9_submission: nil,
        recipient_name: member.display_name,
        recipient_tin_type: "ssn",
        recipient_tin_last4: "0000",
        recipient_address_line1: "—",
        recipient_city: "—",
        recipient_state: "—",
        recipient_zip: "00000",
        recipient_e_delivery_consented: false
      )
    end
  end

  def self.snapshot_payer_from(form, payer)
    form.assign_attributes(
      payer_name: payer.legal_name.to_s,
      payer_ein_last4: payer.ein_last4.to_s,
      payer_address_line1: payer.address_line1.to_s,
      payer_address_line2: payer.address_line2,
      payer_city: payer.city.to_s,
      payer_state: payer.state.to_s,
      payer_zip: payer.zip.to_s,
      payer_phone: payer.phone
    )
  end

  # True when the form has enough real data to actually deliver:
  # a W-9 with a real TIN, and the amount at/above the threshold.
  def deliverable?
    w9_submission_id.present? && recipient_tin_last4 != "0000" && !under_threshold?
  end

  # Mark this form ready to send. Doesn't send anything; queues it into the
  # "delivered" bucket instead once the recipient copy actually goes out.
  def mark_ready!
    update!(status: "ready")
  end

  def mark_delivered!
    update!(status: "delivered", delivered_at: Time.current)
  end

  def mark_filed!(reference: nil, notes: nil)
    update!(status: "filed", filed_at: Time.current, filing_reference: reference.presence, filing_notes: notes.presence)
  end

  def void!
    update!(status: "void")
  end
end
