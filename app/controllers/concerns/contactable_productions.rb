# frozen_string_literal: true

# The productions this person can write to the team of, as a performer: the
# Contact-the-team card on the one Messages page (and My's thread pages).
module ContactableProductions
  extend ActiveSupport::Concern

  private

  # Get productions where user is in the talent pool (can contact the team)
  def productions_user_can_contact
    return [] unless Current.user.person

    people_ids = Current.user.people.active.pluck(:id)
    return [] if people_ids.empty?

    # Get groups user is a member of
    group_ids = GroupMembership.where(person_id: people_ids).pluck(:group_id)

    production_ids = Set.new

    # Productions via person's direct talent pool memberships
    person_production_ids = TalentPoolMembership
      .where(member_type: "Person", member_id: people_ids)
      .joins(:talent_pool)
      .pluck("talent_pools.production_id")
    production_ids.merge(person_production_ids)

    # Productions via shared talent pools
    if people_ids.any?
      shared_person_production_ids = Production
        .joins(talent_pool_shares: { talent_pool: :talent_pool_memberships })
        .where(talent_pool_memberships: { member_type: "Person", member_id: people_ids })
        .pluck(:id)
      production_ids.merge(shared_person_production_ids)
    end

    # Productions via group's talent pool memberships
    if group_ids.any?
      group_production_ids = TalentPoolMembership
        .where(member_type: "Group", member_id: group_ids)
        .joins(:talent_pool)
        .pluck("talent_pools.production_id")
      production_ids.merge(group_production_ids)

      shared_group_production_ids = Production
        .joins(talent_pool_shares: { talent_pool: :talent_pool_memberships })
        .where(talent_pool_memberships: { member_type: "Group", member_id: group_ids })
        .pluck(:id)
      production_ids.merge(shared_group_production_ids)
    end

    # Productions where user is cast in shows (person or group assignments)
    if people_ids.any?
      cast_production_ids = Production
        .joins(shows: :show_person_role_assignments)
        .where(show_person_role_assignments: { assignable_type: "Person", assignable_id: people_ids })
        .distinct
        .pluck(:id)
      production_ids.merge(cast_production_ids)
    end

    if group_ids.any?
      group_cast_production_ids = Production
        .joins(shows: :show_person_role_assignments)
        .where(show_person_role_assignments: { assignable_type: "Group", assignable_id: group_ids })
        .distinct
        .pluck(:id)
      production_ids.merge(group_cast_production_ids)
    end

    Production.where(id: production_ids).order(:name)
  end
end
