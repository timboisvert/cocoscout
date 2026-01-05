# frozen_string_literal: true

class Role < ApplicationRecord
  # Role categories (performing = on stage, technical = backstage/crew)
  CATEGORIES = %w[performing technical].freeze

  # Payment types for roles
  PAYMENT_TYPES = %w[non_paying flat_rate per_ticket per_ticket_with_minimum].freeze

  belongs_to :production
  belongs_to :show, optional: true  # nil for production-level roles, set for show-specific roles

  has_many :show_person_role_assignments, dependent: :destroy
  has_many :shows, through: :show_person_role_assignments

  has_many :role_eligibilities, dependent: :destroy
  has_many :vacancies, class_name: "RoleVacancy", dependent: :destroy
  has_many :show_cast_notifications, dependent: :destroy

  # Scopes for production vs show-specific roles
  scope :production_roles, -> { where(show_id: nil) }
  scope :show_roles, -> { where.not(show_id: nil) }
  scope :for_show, ->(show) { where(show_id: show.id) }

  # Scopes for role categories
  scope :performing, -> { where(category: "performing") }
  scope :technical, -> { where(category: "technical") }

  validates :name, presence: true
  validates :name, uniqueness: { scope: [ :production_id, :show_id ], message: "already exists" }
  validates :quantity, presence: true, numericality: { greater_than: 0, less_than_or_equal_to: 20 }
  validates :category, presence: true, inclusion: { in: CATEGORIES }
  validates :payment_type, presence: true, inclusion: { in: PAYMENT_TYPES }
  validates :payment_amount, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :payment_rate, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :payment_minimum, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  default_scope { order(position: :asc, created_at: :asc) }

  # Check if this is a show-specific role
  def show_role?
    show_id.present?
  end

  # Check if this is a production-level role
  def production_role?
    show_id.nil?
  end

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

  # Multi-person role methods

  # Returns the total number of slots for this role
  def total_slots
    quantity
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

  # Check if this role has room for more assignments
  def has_open_slots?(show)
    slots_remaining(show) > 0
  end

  # Payment helper methods

  def paying?
    payment_type != "non_paying"
  end

  def flat_rate?
    payment_type == "flat_rate"
  end

  def per_ticket?
    payment_type == "per_ticket" || payment_type == "per_ticket_with_minimum"
  end

  def has_minimum?
    payment_type == "per_ticket_with_minimum"
  end
end
