# frozen_string_literal: true

# A manager records a W-9 the org already has — signed on paper, or through
# another system — for a staff member: the file itself, plus the fields a
# 1099 needs, typed in from it. It becomes their current W-9 exactly like one
# filled in online (and a later online one replaces it). Used by the add-staff
# wizard's Tax info step and the staff page's Taxes tab.
#
#   upload = StaffW9Upload.new(staff_member:, uploaded_by: Current.user, params: params[:w9])
#   upload.save  # => true, or false with upload.errors
class StaffW9Upload
  FIELDS = %i[legal_name business_name tax_classification llc_tax_class other_classification
              tin_type tin address_line1 address_line2 city state zip].freeze

  attr_reader :submission

  def initialize(staff_member:, uploaded_by:, params:)
    @staff_member = staff_member
    @uploaded_by = uploaded_by
    @params = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : (params || {}).to_h
    @params = @params.with_indifferent_access
  end

  def save
    @submission = W9Submission.new(attributes)
    @submission.document.attach(@params[:document]) if @params[:document].present?
    return false unless @submission.valid?

    @submission.submit!
    true
  rescue ActiveRecord::RecordInvalid
    false
  end

  def errors
    @submission ? @submission.errors : ActiveModel::Errors.new(W9Submission.new)
  end

  def error_sentence
    errors.full_messages.to_sentence
  end

  # The typed-in values, for putting the form back as it was after an error.
  def values
    @params.slice(*FIELDS.map(&:to_s), "signed_on", "e_delivery", "backup_withholding")
  end

  private

  def attributes
    @params.slice(*FIELDS.map(&:to_s)).merge(
      organization: @staff_member.organization,
      person: @staff_member.person,
      organization_staff_member: @staff_member,
      source: "uploaded",
      uploaded_by: @uploaded_by,
      signed_at: signed_at,
      e_delivery_consented_at: (@params[:e_delivery] == "1" ? Time.current : nil),
      subject_to_backup_withholding: @params[:backup_withholding] == "1"
    )
  end

  # The date on the paper form. Unreadable or missing reads as today: the
  # record is "a W-9 we have as of now", and the form itself is attached.
  def signed_at
    date = Date.iso8601(@params[:signed_on].to_s) rescue nil
    date = nil if date && date > Date.current
    (date || Date.current).in_time_zone.change(hour: 12)
  end
end
