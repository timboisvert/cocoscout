# frozen_string_literal: true

class Production < ApplicationRecord
  # Delete cast_assignment_stages first since they reference both audition_cycles and talent_pools
  before_destroy :delete_cast_assignment_stages
  before_destroy :delete_talent_pool_memberships

  has_many :posters, dependent: :destroy
  has_many :shows, dependent: :destroy
  has_many :event_linkages, dependent: :destroy
  has_many :audition_cycles, dependent: :destroy
  has_many :audition_requests, through: :audition_cycles
  has_many :talent_pools, dependent: :delete_all
  has_many :talent_pool_shares, dependent: :destroy
  has_many :roles, -> { where(show_id: nil) }, dependent: :delete_all  # Production-level roles only
  has_many :all_roles, class_name: "Role", dependent: false  # All roles including show-specific
  has_many :show_person_role_assignments, through: :shows
  has_many :production_permissions, dependent: :delete_all
  has_many :team_invitations, dependent: :destroy
  has_many :questionnaires, dependent: :destroy
  has_many :sign_up_forms, dependent: :destroy
  has_many :payout_schemes, dependent: :destroy
  has_many :show_payouts, through: :shows
  has_many :production_expenses, dependent: :destroy
  has_many :production_ticketing_setups, dependent: :destroy

  # Payroll and advances
  has_one :payroll_schedule, dependent: :destroy
  has_many :payroll_runs, dependent: :destroy
  has_many :person_advances, dependent: :destroy

  # Agreements
  belongs_to :agreement_template, optional: true
  has_many :agreement_signatures, dependent: :destroy

  belongs_to :organization
  belongs_to :contract, optional: true

  has_one_attached :logo, dependent: :purge_later do |attachable|
    # Force JPEG output to handle unusual formats like .jfif
    attachable.variant :small, resize_to_limit: [ 300, 200 ], format: :jpeg, saver: { quality: 85 }, preprocessed: true
  end

  # Rich text for production-wide notes
  has_rich_text :notes

  normalizes :contact_email, with: ->(e) { e.strip.downcase }

  # Casting source determines how performers are assigned to shows in this production
  # Talent pool now includes click-to-add functionality (formerly hybrid behavior)
  enum :casting_source, {
    talent_pool: "talent_pool",   # Traditional casting from production members (with click-to-add)
    sign_up: "sign_up",           # Self-service registration via sign-up forms
    manual: "manual"              # Admin manually adds names/emails
  }, default: :talent_pool, prefix: :casting

  # Production type: in-house (our production) or third-party (renter/contractor)
  enum :production_type, {
    in_house: "in_house",
    third_party: "third_party"
  }, default: :in_house, prefix: :type

  validates :name, presence: true
  validates :contact_email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates :public_key, uniqueness: true, allow_nil: true
  validates :public_key,
            format: { with: /\A[a-z0-9][a-z0-9-]{2,29}\z/, message: "must be 3-30 characters, lowercase letters, numbers, and hyphens only" }, allow_blank: true
  validate :public_key_not_reserved
  validate :public_key_change_frequency
  validate :logo_content_type

  # Callbacks
  before_validation :generate_public_key, on: :create
  before_validation :downcase_public_key
  before_save :track_public_key_change
  after_create :create_default_talent_pool

  # Cache invalidation
  after_commit :invalidate_caches

  # Each production has exactly one talent pool
  # This is the canonical way to access it
  def talent_pool
    talent_pools.first || create_default_talent_pool
  end

  # Returns the shared talent pool if this production is linked to one,
  # otherwise returns its own talent pool
  # If organization is in single talent pool mode, returns the org pool
  def effective_talent_pool
    # Check organization-level setting first
    if organization.talent_pool_single?
      return organization.talent_pool
    end

    # Per-production mode: check for shared pool, then own pool
    shared_pool = TalentPoolShare.find_by(production_id: id)&.talent_pool
    shared_pool || talent_pool
  end

  # Returns true if this production uses a shared talent pool from another production
  def uses_shared_pool?
    TalentPoolShare.exists?(production_id: id)
  end

  # Returns IDs for the effective talent pool (shared or own)
  # Useful for queries that need talent_pool_id IN (...)
  def effective_talent_pool_ids
    [ effective_talent_pool.id ]
  end

  # Returns all unique people assigned to any show in this production
  # Includes both direct Person assignments and Group member expansions
  def cast_people
    # Get person IDs directly assigned to shows
    person_ids = show_person_role_assignments
      .where(assignable_type: "Person")
      .pluck(:assignable_id)
      .uniq

    # Get group IDs assigned to shows, then expand to their members
    group_ids = show_person_role_assignments
      .where(assignable_type: "Group")
      .pluck(:assignable_id)
      .uniq

    if group_ids.any?
      group_member_ids = GroupMembership.where(group_id: group_ids).pluck(:person_id)
      person_ids = (person_ids + group_member_ids).uniq
    end

    Person.where(id: person_ids)
  end

  # Returns true if this production's talent pool is shared with other productions
  def shares_talent_pool?
    talent_pool.talent_pool_shares.exists?
  end

  # Returns all productions that share the same effective talent pool
  def shared_pool_productions
    effective_talent_pool.all_productions.where.not(id: id)
  end

  # Sibling productions in the same organization (for sharing UI)
  def sibling_productions
    organization.productions.where.not(id: id).order(:name)
  end

  def active_audition_cycle
    audition_cycles.find_by(active: true)
  end

  # For backwards compatibility during transition
  def audition_cycle
    active_audition_cycle
  end

  def audition_sessions
    active_audition_cycle&.audition_sessions || AuditionSession.none
  end

  def cast_assignment_stages
    active_audition_cycle&.cast_assignment_stages || CastAssignmentStage.none
  end

  def initials
    return "" if name.blank?

    name.split.map { |word| word[0] }.join.upcase
  end

  def next_show
    shows.where("date_and_time > ?", Time.current).order(:date_and_time).first
  end

  def primary_poster
    posters.find_by(is_primary: true)
  end

  # Cached count of roles for this production
  # Used in cast percentage calculations and other aggregate views
  def cached_roles_count
    Rails.cache.fetch([ "production_roles_count_v1", id, roles.maximum(:updated_at) ], expires_in: 30.minutes) do
      roles.count
    end
  end

  # Count of unique members in the talent pool
  def talent_pool_member_count
    talent_pool&.members&.count || 0
  end

  def safe_logo_variant(variant_name)
    return nil unless logo.attached?

    logo.variant(variant_name)
  rescue ActiveStorage::InvariableError, ActiveStorage::FileNotFoundError => e
    Rails.logger.error("Failed to generate variant for production #{id} logo: #{e.message}")
    nil
  end

  def invalidate_caches
    # Invalidate dashboard cache
    Rails.cache.delete("production_dashboard_#{id}")
    # Invalidate public profile cache
    Rails.cache.delete(public_profile_cache_key)
    # Invalidate roles count cache - use explicit key pattern
    # The cache key is: ["production_roles_count_v1", id, roles.maximum(:updated_at)]
    # Since we can't predict the timestamp, we need a different approach
    # Touch updated_at to invalidate via cache key versioning
  end

  # Cache key for public profile - used for HTTP caching and fragment caching
  def public_profile_cache_key
    "production_public_profile_v1_#{id}"
  end

  # Get the last modified time for public profile caching
  # Considers production itself, posters, shows, and cast members
  def public_profile_last_modified
    timestamps = [ updated_at ]

    # Include poster updates
    if posters.any?
      timestamps << posters.maximum(:updated_at)
    end

    # Include show updates for upcoming shows
    upcoming = shows.where("date_and_time > ?", Time.current)
    if upcoming.any?
      timestamps << upcoming.maximum(:updated_at)
    end

    # Include talent pool updates (affects cast members)
    if talent_pool
      timestamps << talent_pool.updated_at
    end

    timestamps.compact.max || updated_at
  end

  # ETag for HTTP caching
  def public_profile_etag
    Digest::MD5.hexdigest([
      id,
      public_profile_last_modified.to_i,
      show_cast_members,
      show_upcoming_events,
      public_profile_enabled
    ].join("-"))
  end

  # Public profile methods
  def update_public_key(new_key)
    return false if new_key == public_key

    old_keys_array = old_keys.present? ? JSON.parse(old_keys) : []
    old_keys_array << public_key unless old_keys_array.include?(public_key)

    self.public_key = new_key
    self.old_keys = old_keys_array.to_json
    save
  end

  # Get parsed event visibility overrides hash
  def parsed_event_visibility_overrides
    return {} if event_visibility_overrides.blank?

    JSON.parse(event_visibility_overrides)
  rescue JSON::ParserError
    {}
  end

  # Check if an event type is publicly visible for this production
  # Uses the unified show_upcoming_events settings
  def event_type_publicly_visible?(event_type)
    # If show_upcoming_events is disabled, nothing is visible
    return false unless show_upcoming_events?

    # If mode is "all", all event types are visible
    return true if show_all_upcoming_event_types?

    # If mode is "specific", check if this event type is in the list
    show_upcoming_event_type?(event_type)
  end

  # Get all shows that are publicly visible for this production
  def publicly_visible_shows
    shows.where(canceled: false).select do |show|
      show.public_profile_visible?
    end
  end

  # Get upcoming shows that are publicly visible
  def publicly_visible_upcoming_shows
    publicly_visible_shows.select { |show| show.date_and_time > Time.current }
  end

  # Get parsed cast talent pool IDs array
  def parsed_cast_talent_pool_ids
    return [] if cast_talent_pool_ids.blank?

    JSON.parse(cast_talent_pool_ids)
  rescue JSON::ParserError
    []
  end

  # Set cast talent pool IDs from array
  def cast_talent_pool_ids_array=(ids)
    self.cast_talent_pool_ids = ids.present? ? ids.to_json : nil
  end

  # Check if the talent pool should be shown (for backwards compatibility)
  def show_all_talent_pools?
    true
  end

  # Get the talent pool to display cast from
  def displayable_talent_pools
    talent_pool ? [ talent_pool ] : []
  end

  # Get unique cast members (people and groups) from the talent pool
  # Returns an array of mixed Person and Group objects
  def public_cast_members
    return [] unless show_cast_members?
    return [] unless talent_pool

    memberships = talent_pool.talent_pool_memberships

    # Get unique member_type/member_id pairs
    member_refs = memberships.pluck(:member_type, :member_id).uniq

    # Group by type and fetch
    person_ids = member_refs.select { |type, _| type == "Person" }.map(&:last)
    group_ids = member_refs.select { |type, _| type == "Group" }.map(&:last)

    people = Person.where(id: person_ids)
    groups = Group.where(id: group_ids)

    # Combine and sort by name
    (people.to_a + groups.to_a).sort_by(&:name)
  end

  # Get parsed upcoming event types array
  def parsed_show_upcoming_event_types
    return [] if show_upcoming_event_types.blank?

    JSON.parse(show_upcoming_event_types)
  rescue JSON::ParserError
    []
  end

  # Check if all event types should be shown for upcoming events (empty means all)
  def show_all_upcoming_event_types?
    show_upcoming_events_mode.blank? || show_upcoming_events_mode == "all"
  end

  # Check if a specific event type should be shown in upcoming events
  def show_upcoming_event_type?(event_type)
    return true if show_all_upcoming_event_types?

    parsed_show_upcoming_event_types.include?(event_type.to_s)
  end

  def create_default_talent_pool
    talent_pools.create!(name: "Talent Pool")
  end

  # Contract-related helpers
  def third_party?
    type_third_party?
  end

  def governed_by_contract?
    contract.present? && contract.status_active?
  end

  def contract_locked?
    governed_by_contract?
  end

  # Check if ticketing is available for this production
  # In-house productions always have ticketing
  # Third-party productions need Ticketing service enabled in their contract
  def ticketing_enabled?
    return true unless third_party?  # In-house productions always have ticketing

    # Third-party needs contract with Ticketing service
    return false unless contract.present?

    contract.draft_services.any? { |s| s["name"]&.downcase&.include?("ticketing") }
  end

  # Agreement methods

  # Returns true if this production requires performers to sign an agreement
  def agreement_required?
    agreement_required && agreement_template.present?
  end

  # Returns the agreement content for this production
  def agreement_content
    agreement_template&.content
  end

  # Render agreement with variables substituted for a specific person
  def rendered_agreement_content(person = nil)
    return nil unless agreement_template

    variables = {
      production_name: name,
      organization_name: organization.name,
      performer_name: person&.name || "Performer",
      current_date: Date.current.strftime("%B %-d, %Y")
    }
    agreement_template.render_content(variables)
  end

  # Check if a person has signed the agreement
  def agreement_signed_by?(person)
    agreement_signatures.exists?(person: person)
  end

  # Get signature for a person
  def agreement_signature_for(person)
    agreement_signatures.find_by(person: person)
  end

  # People in talent pool who haven't signed
  def people_without_agreement_signature
    return Person.none unless agreement_required?

    signed_person_ids = agreement_signatures.pluck(:person_id)
    member_ids = effective_talent_pool.members.select { |m| m.is_a?(Person) }.map(&:id)
    Person.where(id: member_ids).where.not(id: signed_person_ids)
  end

  # People in talent pool who have signed
  def people_with_agreement_signature
    return Person.none unless agreement_required?

    signed_person_ids = agreement_signatures.pluck(:person_id)
    member_ids = effective_talent_pool.members.select { |m| m.is_a?(Person) }.map(&:id)
    Person.where(id: member_ids).where(id: signed_person_ids)
  end

  # Count of signed vs total in talent pool
  def agreement_signature_stats
    return { signed: 0, total: 0, percent: 100 } unless agreement_required?

    total = effective_talent_pool.members.select { |m| m.is_a?(Person) }.count
    signed = agreement_signatures.count
    percent = total > 0 ? (signed * 100.0 / total).round : 100

    { signed: signed, total: total, percent: percent }
  end

  private

  def generate_public_key
    return if public_key.present?
    return if name.blank? # Can't generate without a name

    self.public_key = PublicKeyService.generate(name)
  end

  def downcase_public_key
    self.public_key = public_key.downcase if public_key.present?
  end

  def public_key_not_reserved
    return if public_key.blank?

    reserved = YAML.safe_load_file(
      Rails.root.join("config", "reserved_public_keys.yml"),
      permitted_classes: [],
      permitted_symbols: [],
      aliases: true
    )
    return unless reserved.include?(public_key)

    errors.add(:public_key, "is reserved for CocoScout system pages")
  end

  def public_key_change_frequency
    return if public_key_was.nil? || public_key == public_key_was # No change or new record
    return if public_key_changed_at.nil? # First time changing

    cooldown_days = YAML.load_file(Rails.root.join("config", "profile_settings.yml"))["url_change_cooldown_days"]
    days_since_last_change = (Time.current - public_key_changed_at) / 1.day
    return unless days_since_last_change < cooldown_days

    errors.add(:public_key, "was changed too recently.")
  end

  def track_public_key_change
    return unless public_key_changed? && !new_record?

    # Store the old key
    old_keys_array = old_keys.present? ? JSON.parse(old_keys) : []
    old_key = public_key_was

    # Add the old key to the array if it's not already there and not nil
    if old_key.present? && !old_keys_array.include?(old_key)
      old_keys_array << old_key
      self.old_keys = old_keys_array.to_json
    end

    # Update the timestamp
    self.public_key_changed_at = Time.current
  end

  def delete_cast_assignment_stages
    # Delete all cast_assignment_stages for all audition_cycles in this production
    CastAssignmentStage.where(audition_cycle_id: audition_cycles.pluck(:id)).delete_all
  end

  def delete_talent_pool_memberships
    # Delete all talent_pool_memberships for this production's talent pool
    TalentPoolMembership.joins(:talent_pool).where(talent_pools: { production_id: id }).delete_all

    # Delete all auditions before deleting audition_requests or audition_sessions
    # Auditions reference both audition_requests and audition_sessions
    audition_session_ids = AuditionSession.joins(:audition_cycle).where(audition_cycles: { production_id: id }).pluck(:id)
    Audition.where(audition_session_id: audition_session_ids).delete_all
  end

  def logo_content_type
    return unless logo.attached? && !logo.content_type.in?(%w[image/jpeg image/jpg image/png])

    errors.add(:logo, "Logo must be a JPEG, JPG, or PNG file")
  end
end
