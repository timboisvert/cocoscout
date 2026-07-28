# frozen_string_literal: true

# Opt-in membership: this Person is part of the org's house staff and can be
# assigned to shifts. Distinct from cast assignments / talent pools.
class OrganizationStaffMember < ApplicationRecord
  ONBOARDING_STATES = %w[added invited completed].freeze

  belongs_to :organization
  belongs_to :person
  # A staff member can report to another staff member in the same org.
  belongs_to :manager, class_name: "OrganizationStaffMember", optional: true
  has_many :reports, class_name: "OrganizationStaffMember", foreign_key: :manager_id, dependent: :nullify

  has_many :staff_role_qualifications, dependent: :destroy
  has_many :house_roles, through: :staff_role_qualifications

  validates :person_id, uniqueness: { scope: :organization_id }
  validates :onboarding_state, inclusion: { in: ONBOARDING_STATES }
  validates :hourly_rate_cents, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validate :manager_in_same_org

  scope :active, -> { where(archived_at: nil) }

  # Display name: preferred first name (falls back to legal first) + last name,
  # else the linked Person's display name.
  def display_name
    first = preferred_first_name.presence || first_name.presence
    [ first, last_name.presence ].compact.join(" ").presence || person&.name
  end

  def hourly_rate_dollars
    hourly_rate_cents ? hourly_rate_cents / 100.0 : nil
  end

  # Parse a dollar string ("$15", "15.50") to cents; nil/blank → nil.
  def self.rate_cents_from(value)
    return nil if value.blank?

    (value.to_s.delete("$,").to_d * 100).round
  end

  # What this member earns for a given house role: the role's own rate, falling
  # back to their default hourly rate when the role rate isn't set.
  def rate_cents_for(house_role)
    return hourly_rate_cents if house_role.nil?

    qualification = staff_role_qualifications.detect { |q| q.house_role_id == house_role.id } ||
                    staff_role_qualifications.find_by(house_role_id: house_role.id)
    qualification&.hourly_rate_cents || hourly_rate_cents
  end

  # Set which house roles this member can fill and each one's pay rate in one go.
  # role_ids: array of house_role ids. rates: hash of house_role_id => dollars
  # (string or number); a blank/missing rate means "use the default".
  def sync_role_qualifications!(role_ids:, rates: {})
    rates = (rates || {}).transform_keys(&:to_i)
    ids = Array(role_ids).map(&:to_i).reject(&:zero?).uniq
    valid_roles = organization.house_roles.where(id: ids)

    staff_role_qualifications.where.not(house_role_id: valid_roles.select(:id)).destroy_all

    valid_roles.each do |role|
      qualification = staff_role_qualifications.find_or_initialize_by(house_role_id: role.id)
      # An explicit rate wins; otherwise fall back to the role's default pay.
      qualification.hourly_rate_cents =
        self.class.rate_cents_from(rates[role.id]) || role.default_hourly_rate_cents
      qualification.save!
    end
  end

  # Computed live from the two real requirements (accepted + bank connected) so a
  # stale cached `onboarding_state` can never leave someone stuck as "pending"
  # after they've actually finished. `onboarding_state` is kept as a cache/hint
  # (badge labels, resend copy) but is not authoritative for completion.
  def onboarding_completed?
    acknowledged? && bank_connected?
  end

  # "Pending" = added or invited but not yet finished onboarding (no claimed
  # account / not set up). These live in a separate section on the staff hub.
  def pending_onboarding?
    !onboarding_completed?
  end

  # They've accepted onboarding on their welcome page.
  def acknowledged?
    acknowledged_at.present?
  end

  # Their bank (Stripe Connect) is ready to receive payouts.
  def bank_connected?
    person&.can_receive_payouts? || false
  end

  # Onboarding is only "done" when they've BOTH acknowledged and connected a
  # bank — connecting a bank alone isn't the same as accepting the role. Call
  # this whenever either side changes (acknowledge action, Stripe webhook).
  def refresh_onboarding_state!
    return if onboarding_state == "added" && !acknowledged? # never invited/engaged yet

    update!(onboarding_state: acknowledged? && bank_connected? ? "completed" : "invited")
  end

  # A finer-grained status for the staff list than the coarse onboarding_state.
  # Reads the *live* bank state (person.can_receive_payouts?) rather than the
  # cached onboarding_state, so connecting a bank anywhere — My Payments, the
  # onboarding screen, or a Stripe sync — clears "awaiting bank" immediately.
  # :no_account → invited but hasn't claimed a CocoScout account
  # :invited → account exists but hasn't accepted onboarding
  # :awaiting_bank → accepted, still needs to connect a bank
  # :onboarded → accepted and bank connected
  def onboarding_status
    return :no_account if person&.user.nil?
    return :onboarded if acknowledged? && bank_connected?
    return :awaiting_bank if acknowledged?

    :invited
  end

  def archived?
    archived_at.present?
  end

  def archive!
    update!(archived_at: Time.current)
  end

  def unarchive!
    update!(archived_at: nil)
  end

  private

  def manager_in_same_org
    return if manager.nil?

    errors.add(:manager, "must belong to the same organization") if manager.organization_id != organization_id
  end
end
