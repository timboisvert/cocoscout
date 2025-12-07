# frozen_string_literal: true

class ShoutoutSearchService
  def initialize(query, current_user, url_helper = nil)
    @query = query.to_s.strip
    @current_user = current_user
    @url_helper = url_helper
  end

  def call
    return [] if @query.length < 2

    people = search_people
    groups = search_groups

    (people + groups).sort_by { |r| r[:name] }
  end

  private

  def search_people
    Person.where("name LIKE ?", "%#{@query}%")
          .where.not(id: @current_user.person.id)
          .limit(10)
          .map { |person| person_to_json(person) }
  end

  def search_groups
    member_group_ids = @current_user.person.groups.pluck(:id)

    Group.where("name LIKE ?", "%#{@query}%")
         .where(archived_at: nil)
         .where.not(id: member_group_ids)
         .limit(10)
         .map { |group| group_to_json(group) }
  end

  def person_to_json(person)
    headshot_variant = person.safe_headshot_variant(:thumb)
    headshot_url = (@url_helper.call(headshot_variant) if headshot_variant && @url_helper)

    {
      type: "Person",
      id: person.id,
      name: person.name,
      public_key: person.public_key,
      initials: person.initials,
      headshot_url: headshot_url
    }
  end

  def group_to_json(group)
    headshot_url = nil
    if group.headshot&.attached? && @url_helper
      variant = group.headshot.variant(resize_to_limit: [ 200, 200 ])
      headshot_url = @url_helper.call(variant)
    end

    {
      type: "Group",
      id: group.id,
      name: group.name,
      public_key: group.public_key,
      initials: group.initials,
      headshot_url: headshot_url
    }
  end
end
