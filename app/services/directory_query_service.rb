# frozen_string_literal: true

# Service object for handling all directory query logic
# Centralizes filtering, searching, sorting, and segmentation
class DirectoryQueryService
  attr_reader :params, :organization, :production

  def initialize(params, organization, production = nil)
    @params = params
    @organization = organization
    @production = production
  end

  def call
    people = base_people_query
    groups = base_groups_query

    # Apply filters
    people, groups = apply_type_filter(people, groups)
    people, groups = apply_scope_filter(people, groups)
    people, groups = apply_search(people, groups)

    # Apply sorting
    people = apply_sort(people)
    groups = apply_sort(groups)

    [ people, groups ]
  end

  private

  def base_people_query
    organization.people
  end

  def base_groups_query
    organization.groups
                .where(archived_at: nil)
  end

  def apply_type_filter(people, groups)
    case params[:type]
    when "people"
      [ people, Group.none ]
    when "groups"
      [ Person.none, groups ]
    else # "all"
      [ people, groups ]
    end
  end

  def apply_scope_filter(people, groups)
    case params[:filter]
    when "current_production"
      return [ Person.none, Group.none ] unless production

      people = people.joins(:talent_pools)
                     .where(talent_pools: { production_id: production.id })
                     .distinct
      groups = groups.joins(:talent_pools)
                     .where(talent_pools: { production_id: production.id })
                     .distinct
    when "org_talent_pools"
      people = people.joins(:talent_pools).distinct
      groups = groups.joins(:talent_pools).distinct
    when "everyone"
      # No additional filtering
    end

    [ people, groups ]
  end

  def apply_search(people, groups)
    return [ people, groups ] if params[:q].blank?

    query = "%#{params[:q].downcase}%"
    people = people.where("LOWER(people.name) LIKE ? OR LOWER(people.email) LIKE ?", query, query)
    groups = groups.where("LOWER(groups.name) LIKE ? OR LOWER(groups.email) LIKE ?", query, query)

    [ people, groups ]
  end

  def apply_sort(relation)
    case params[:order]
    when "newest"
      relation.order(created_at: :desc)
    when "oldest"
      relation.order(created_at: :asc)
    else # "alphabetical"
      relation.order(name: :asc)
    end
  end
end
