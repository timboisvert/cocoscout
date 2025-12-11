# frozen_string_literal: true

class Role < ApplicationRecord
  belongs_to :production
  belongs_to :show, optional: true  # nil for production-level roles, set for show-specific roles

  has_many :show_person_role_assignments, dependent: :destroy
  has_many :shows, through: :show_person_role_assignments

  has_many :role_eligibilities, dependent: :destroy
  has_many :vacancies, class_name: "RoleVacancy", dependent: :destroy

  # Scopes for production vs show-specific roles
  scope :production_roles, -> { where(show_id: nil) }
  scope :show_roles, -> { where.not(show_id: nil) }
  scope :for_show, ->(show) { where(show_id: show.id) }

  validates :name, presence: true
  validates :name, uniqueness: { scope: [ :production_id, :show_id ], message: "already exists" }

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
end
