# frozen_string_literal: true

class Role < ApplicationRecord
  # Role categories (performing = on stage, technical = backstage/crew,
  # break = a running-order marker such as an intermission in an act-based
  # lineup — never cast, never counted)
  CATEGORIES = %w[performing technical break].freeze
  BREAK_CATEGORY = "break"

  # System role types (for system-managed roles)
  SYSTEM_ROLE_TYPES = %w[attendees].freeze

  belongs_to :production
  belongs_to :show, optional: true  # nil for production-level roles, set for show-specific roles

  has_many :show_person_role_assignments, dependent: :destroy
  has_many :shows, through: :show_person_role_assignments

  has_many :role_eligibilities, dependent: :destroy
  has_many :vacancies, class_name: "RoleVacancy", dependent: :destroy
  has_many :show_cast_notifications, dependent: :destroy
  has_many :casting_table_draft_assignments, dependent: :destroy

  # Scopes for production vs show-specific roles
  scope :production_roles, -> { where(show_id: nil) }
  scope :show_roles, -> { where.not(show_id: nil) }
  scope :for_show, ->(show) { where(show_id: show.id) }

  # Scopes for role categories
  scope :performing, -> { where(category: "performing") }
  scope :technical, -> { where(category: "technical") }
  # Everything that takes a performer — excludes intermission-style break markers
  scope :castable, -> { where.not(category: BREAK_CATEGORY) }
  scope :breaks, -> { where(category: BREAK_CATEGORY) }

  # Scopes for system-managed roles
  scope :system_managed, -> { where(system_managed: true) }

  # Standing roles ("Show roles" in the UI — the MC, Stage Kitten ×2) sit
  # outside an act-based lineup: cast per show like any role, but not acts.
  # `lineup` is everything else — the running order in act mode.
  scope :standing, -> { where(standing: true) }
  scope :lineup, -> { where(standing: false) }

  # How a role reads in an act-based lineup editor's Type select: an act in the
  # running order, an intermission marker, or a show role alongside the lineup.
  LINEUP_KINDS = %w[act break show_role].freeze

  validates :name, presence: true
  # An act-based lineup may repeat a name ("Magic" in each half); role-based
  # lineups keep one role per name — and so do show roles, which aren't acts.
  # A show's custom lineup follows the show's effective mode (it may override
  # the production's).
  validates :name, uniqueness: { scope: [ :production_id, :show_id ], message: "already exists" },
            unless: :act?
  validate :break_only_in_act_based_production
  validate :standing_role_takes_performers
  validates :quantity, presence: true, numericality: { greater_than: 0, less_than_or_equal_to: 100 }
  validates :category, presence: true, inclusion: { in: CATEGORIES }
  validates :system_role_type, inclusion: { in: SYSTEM_ROLE_TYPES, allow_nil: true }
  validate :restricted_role_has_eligible_members

  default_scope { order(position: :asc, created_at: :asc) }

  # Attribute to temporarily store eligible member IDs for validation
  attr_accessor :pending_eligible_member_ids

  # Returns all eligible members (people and groups) for this role
  def eligible_members
    return [] unless restricted?

    person_ids = role_eligibilities.where(member_type: "Person").pluck(:member_id)
    group_ids = role_eligibilities.where(member_type: "Group").pluck(:member_id)

    people = Person.where(id: person_ids).includes(profile_headshots: { image_attachment: :blob })
    groups = Group.where(id: group_ids).includes(profile_headshots: { image_attachment: :blob })

    (people.to_a + groups.to_a).sort_by(&:name)
  end

  # Returns just the eligible people (for backward compatibility)
  def eligible_people
    Person.where(id: role_eligibilities.where(member_type: "Person").select(:member_id))
  end

  # Returns just the eligible groups
  def eligible_groups
    Group.where(id: role_eligibilities.where(member_type: "Group").select(:member_id))
  end

  # Check if a specific member (person or group) is eligible
  def eligible?(member)
    return true unless restricted?
    role_eligibilities.exists?(member: member)
  end

  # Returns members who can be assigned to this role for a given set of talent pools.
  # If the role is unrestricted, returns all members from the talent pools.
  # If the role is restricted, returns only the eligible members who are also in the talent pools.
  def eligible_assignees(talent_pool_ids)
    # Get all people from talent pools
    people = Person.joins(:talent_pool_memberships)
                   .where(talent_pool_memberships: { talent_pool_id: talent_pool_ids })
                   .distinct

    # Get all groups from talent pools
    groups = Group.joins(:talent_pool_memberships)
                  .where(talent_pool_memberships: { talent_pool_id: talent_pool_ids })
                  .distinct

    if restricted?
      eligible_person_ids = role_eligibilities.where(member_type: "Person").pluck(:member_id)
      eligible_group_ids = role_eligibilities.where(member_type: "Group").pluck(:member_id)

      filtered_people = people.where(id: eligible_person_ids)
      filtered_groups = groups.where(id: eligible_group_ids)

      (filtered_people.to_a + filtered_groups.to_a).sort_by(&:name)
    else
      (people.to_a + groups.to_a).sort_by(&:name)
    end
  end

  # ---- Act-based lineup support -------------------------------------------
  #
  # In an act-based production a Role is an act in the running order unless
  # it's a "break" (an intermission marker that takes no performer) or a
  # standing role (a "Show role" — the MC, a stage kitten — cast alongside the
  # lineup but not part of it).

  def break?
    category == BREAK_CATEGORY
  end

  def castable?
    !break?
  end

  # Is this role an act? Standing roles never are. Otherwise a show's custom
  # role follows that show's effective casting mode (which may override the
  # production's); a production role follows the production — unless it's
  # being read inside a specific show (pass show:), in which case that show's
  # mode decides. Callers with many roles should preload :show / :production
  # so this doesn't query per role.
  def act?(show: nil)
    return false if standing?

    context = show || (show_id ? self.show : nil)
    return context.act_based? if context

    production&.act_based? || false
  end

  # The act-mode editor's Type select: "act" | "break" | "show_role". Setting
  # it maps onto category + standing in one place so every editor (production
  # roles, a show's lineup, the production wizard) agrees. A show role that
  # was technical stays technical (the flag is what makes it a show role); an
  # act or break clears the flag.
  def lineup_kind
    return "break" if break?
    return "show_role" if standing?

    "act"
  end

  # What a role editor posted, made safe for the lineup it's editing. In an
  # act-based lineup the Type select posts `category` as performing (an act),
  # break (an intermission) or show_role — that becomes lineup_kind, acts and
  # breaks are one slot, and breaks aren't restricted. In a role-based lineup
  # there are no breaks or show roles: either quietly becomes a performing
  # role and `standing` is left alone.
  def self.editor_params(permitted, act_based:)
    permitted = permitted.to_h.with_indifferent_access
    category = permitted.delete(:category).to_s
    if act_based
      kind = case category
      when BREAK_CATEGORY then "break"
      when "show_role" then "show_role"
      else "act"
      end
      permitted[:lineup_kind] = kind
      permitted[:quantity] = 1 unless kind == "show_role"
      permitted[:restricted] = false if kind == "break"
    else
      permitted[:category] = %w[performing technical].include?(category) ? category : "performing"
    end
    permitted
  end

  def lineup_kind=(kind)
    case kind.to_s
    when "break"
      self.category = BREAK_CATEGORY
      self.standing = false
    when "show_role"
      self.category = "performing" unless category == "technical"
      self.standing = true
    else
      self.category = "performing" if break?
      self.standing = false
    end
  end

  # The roles this one is ordered among: a show's custom lineup or the
  # production's default lineup. Ordered by the default scope (position).
  def siblings
    show_id ? Role.where(show_id: show_id) : Role.where(production_id: production_id, show_id: nil)
  end

  # Stable identity for matching a role across lineups (production ↔ show,
  # show ↔ linked show) when names may repeat: the name plus its ordinal among
  # same-named siblings, so the second "Magic" maps to the second "Magic".
  # In a role-based production names are unique and the ordinal is always 1.
  def match_key
    self.class.match_key_for(self, siblings.to_a)
  end

  def self.match_key_for(role, sibling_roles)
    name_key = role.name.to_s.downcase.strip
    same = sibling_roles.select { |r| r.name.to_s.downcase.strip == name_key }
    ordinal = same.index { |r| r.id == role.id } || same.size
    "#{name_key}##{ordinal + 1}"
  end

  # Match keys for a whole lineup at once (avoids N queries): { key => role }.
  def self.match_keys_for(roles)
    list = roles.to_a
    list.index_by { |r| match_key_for(r, list) }
  end

  # 1-based running-order number among castable siblings; nil for breaks.
  # Pass show: when a production role is being read inside one show, so a
  # production lineup rendered on an act-mode night is numbered.
  def lineup_number(show: nil)
    return nil unless act?(show: show)

    self.class.lineup_numbers_for(siblings.to_a)[id]
  end

  # { role_id => number } for a lineup; breaks and standing roles are omitted
  # (neither is numbered — only acts have a place in the running order).
  def self.lineup_numbers_for(roles)
    numbers = {}
    roles.to_a.reject { |r| r.break? || r.standing? }.each_with_index { |r, i| numbers[r.id] = i + 1 }
    numbers
  end

  # How this role reads to a person: "Act 3 · Magic" in an act-based
  # lineup, the plain name otherwise. Pass a precomputed number when
  # rendering many roles (see CastingHelper#lineup_numbers), and show: when
  # rendering inside a specific show so its casting-mode override applies.
  def display_name(number: nil, show: nil)
    return name unless act?(show: show)
    return name if break?

    n = number || lineup_number(show: show)
    n ? "Act #{n} · #{name}" : name
  end

  # Multi-person role methods

  # Returns the total number of slots for this role
  def total_slots
    break? ? 0 : quantity
  end

  # Returns the number of filled slots for this role in a given show
  def filled_slots(show)
    show.show_person_role_assignments.where(role: self).count
  end

  # Returns the number of remaining slots for this role in a given show
  def slots_remaining(show)
    total_slots - filled_slots(show)
  end

  # Check if this role is fully filled for a given show
  def fully_filled?(show)
    filled_slots(show) >= total_slots
  end

  private

  def break_only_in_act_based_production
    return unless break?
    return if act?

    errors.add(:category, "breaks belong to act-based lineups only")
  end

  def standing_role_takes_performers
    return unless standing? && break?

    errors.add(:standing, "an intermission can't be a show role")
  end

  def restricted_role_has_eligible_members
    return unless restricted?

    # Check if pending_eligible_member_ids was explicitly set (even to nil or empty array)
    if instance_variable_defined?(:@pending_eligible_member_ids)
      non_blank_ids = Array(pending_eligible_member_ids).reject(&:blank?)
      if non_blank_ids.empty?
        errors.add(:base, "Restricted roles must have at least one eligible person or group")
      end
    elsif persisted?
      # For existing roles without pending updates, check existing eligibilities
      if role_eligibilities.empty?
        errors.add(:base, "Restricted roles must have at least one eligible person or group")
      end
    else
      # New restricted role without pending members
      errors.add(:base, "Restricted roles must have at least one eligible person or group")
    end
  end
end
