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

  # The employee agreement this member was asked to accept during onboarding.
  belongs_to :staff_agreement_template, optional: true

  validates :person_id, uniqueness: { scope: :organization_id }
  validates :onboarding_state, inclusion: { in: ONBOARDING_STATES }
  validates :hourly_rate_cents, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validate :manager_in_same_org

  scope :active, -> { where(archived_at: nil) }
  # Inactive = still in the system (history, records, My Shifts past shifts all
  # kept) but out of scheduling, pay, availability prompts, and staffing counts.
  scope :inactive, -> { where.not(archived_at: nil) }

  # Display name: preferred first name (falls back to legal first) + last name,
  # else the linked Person's display name.
  def display_name
    first = preferred_first_name.presence || first_name.presence
    [ first, last_name.presence ].compact.join(" ").presence || person&.name
  end

  # The employee agreement to show this member: the org's REQUIRED one if it has
  # designated one (so onboarding signs the right template), else the one they've
  # already signed, else the org's first active template. Nil when none exist.
  def effective_agreement_template
    required_agreement_template ||
      staff_agreement_template ||
      organization&.staff_agreement_templates&.active&.order(:name)&.first
  end

  # The agreement this member is REQUIRED to sign (org-designated, active), or nil.
  def required_agreement_template
    organization&.requires_staff_agreement? ? organization.required_staff_agreement_template : nil
  end

  # Has this member signed the CURRENT version of the org's required agreement?
  def signed_required_agreement?
    tmpl = required_agreement_template
    tmpl.present? &&
      staff_agreement_template_id == tmpl.id &&
      agreed_agreement_version.to_i == tmpl.version
  end

  # Retroactive-enforcement trigger: the org requires an agreement, this member
  # isn't exempt, and they haven't signed the current version. Version-aware — a
  # template version bump flips this back to true until they re-sign.
  def needs_to_sign_agreement?
    required_agreement_template.present? && !agreement_exempt? && !signed_required_agreement?
  end

  # Active members (across the given people) who owe a signature on their org's
  # required agreement. The check is Ruby-level (org pointer + version compare),
  # so we load and filter rather than express it in SQL.
  def self.pending_agreement_signatures(person_ids)
    active.where(person_id: person_ids)
          .includes(:organization, :person, :staff_agreement_template)
          .select(&:needs_to_sign_agreement?)
          .sort_by { |m| m.organization.name.to_s.downcase }
  end

  # Merge values for rendering this member's employee agreement.
  def agreement_variables
    {
      "staff_name"        => display_name.to_s,
      "organization_name" => organization&.name.to_s,
      "title"             => title.to_s,
      "department"        => department.to_s,
      "start_date"        => start_date ? start_date.strftime("%B %-d, %Y") : "",
      "current_date"      => Date.current.strftime("%B %-d, %Y")
    }
  end

  # The agreement this member sees/accepts: the template wording with merge fields
  # filled in, plus a "Schedule 1" spelling out their role(s), pay, and start date.
  def rendered_agreement_html(template = effective_agreement_template)
    return nil unless template

    template.render_content(agreement_variables) + agreement_schedule_html
  end

  # "Schedule 1" appended to the agreement — the member's role(s), pay rate(s), and
  # start date — so the agreement they accept actually describes what they're doing.
  def agreement_schedule_html
    roles = staff_role_qualifications.includes(:house_role).map(&:house_role).compact
    return "".html_safe if roles.empty? && title.blank? && start_date.blank?

    esc = ->(s) { ERB::Util.html_escape(s.to_s) }
    parts = [ "<div><br></div>", "<div><strong>Schedule 1 &mdash; Services</strong></div>" ]
    parts << "<div>Position: #{esc.call(title)}</div>" if title.present?
    if roles.any?
      items = roles.map do |role|
        label = rate_label_for(role)
        rate = label ? " &mdash; #{label}" : ""
        "<li>#{esc.call(role.name)}#{rate}</li>"
      end
      parts << "<div>Role(s):</div><ul>#{items.join}</ul>"
    end
    parts << "<div>Start date: #{esc.call(start_date.strftime('%B %-d, %Y'))}</div>" if start_date.present?
    parts.join.html_safe
  end

  def agreed_to_agreement?
    agreed_agreement_version.present?
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

    qualification_for(house_role)&.hourly_rate_cents || hourly_rate_cents
  end

  # A flat role's amount for one shift: this member's override, else the role's
  # default. nil when the role isn't flat.
  def flat_cents_for(house_role)
    return nil unless house_role&.flat?

    qualification_for(house_role)&.flat_rate_cents || house_role.default_flat_rate_cents
  end

  # THE pricing question: what is this person owed for this work?
  #
  # Every screen that shows money for staffing goes through here, so an hourly
  # role and a flat one can't disagree between the timesheet, the pay grid and
  # the payout run. A flat role ignores hours entirely — that's the point of it.
  def amount_cents_for(house_role, hours:)
    flat = flat_cents_for(house_role)
    return flat.to_i if flat

    (hours.to_d * rate_cents_for(house_role).to_i).round
  end

  # What this member's pay for a role reads as: "$20.00/hr" or "$50.00/night".
  def rate_label_for(house_role)
    if house_role&.flat?
      cents = flat_cents_for(house_role)
      cents ? "$#{format('%.2f', cents / 100.0)}/night" : nil
    else
      cents = rate_cents_for(house_role)
      cents ? "$#{format('%.2f', cents / 100.0)}/hr" : nil
    end
  end

  def qualification_for(house_role)
    staff_role_qualifications.detect { |q| q.house_role_id == house_role.id } ||
      staff_role_qualifications.find_by(house_role_id: house_role.id)
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
      # A flat role carries its own amount; the same explicit rate applies to
      # whichever kind of pay the role actually uses.
      if role.flat?
        qualification.flat_rate_cents =
          self.class.rate_cents_from(rates[role.id]) || role.default_flat_rate_cents
      end
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

  # The user-facing concept is "inactive", not deleted: roles, rates, manager,
  # and all history survive; reactivating restores everything untouched.
  alias_method :inactive?, :archived?
  alias_method :deactivate!, :archive!
  alias_method :reactivate!, :unarchive!

  private

  def manager_in_same_org
    return if manager.nil?

    errors.add(:manager, "must belong to the same organization") if manager.organization_id != organization_id
  end
end
