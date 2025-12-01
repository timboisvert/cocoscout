class Api::SearchController < ApplicationController
  before_action :require_authentication

  def people_and_groups
    query = params[:q].to_s.strip

    if query.length < 2
      render json: []
      return
    end

    results = []

    # Search for people
    people = Person.where("name LIKE ?", "%#{query}%")
                   .where.not(id: Current.user.person.id)
                   .limit(10)
                   .map do |person|
      {
        type: "Person",
        id: person.id,
        name: person.name,
        public_key: person.public_key,
        initials: person.initials,
        headshot_url: person.safe_headshot_variant(:thumb) ? url_for(person.safe_headshot_variant(:thumb)) : nil
      }
    end

    # Search for groups
    groups = Group.where("name LIKE ?", "%#{query}%")
                  .where(archived_at: nil)
                  .limit(10)
                  .map do |group|
      headshot_url = nil
      if group.headshot&.attached?
        headshot_url = url_for(group.headshot.variant(resize_to_limit: [ 200, 200 ]))
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

    results = (people + groups).sort_by { |r| r[:name] }

    render json: results
  end

  def check_existing_shoutout
    shoutee_type = params[:shoutee_type]
    shoutee_id = params[:shoutee_id]

    if shoutee_type.blank? || shoutee_id.blank?
      render json: { has_existing_shoutout: false }
      return
    end

    shoutee = case shoutee_type
    when "Person"
      Person.find_by(id: shoutee_id)
    when "Group"
      Group.find_by(id: shoutee_id)
    end

    if shoutee.nil?
      render json: { has_existing_shoutout: false }
      return
    end

    # Check if user has already given this person/group a shoutout
    has_existing = Current.user.person.given_shoutouts
      .where(shoutee: shoutee)
      .where(id: Shoutout.left_joins(:replacement).where(replacement: { id: nil }).select(:id))
      .exists?

    render json: { has_existing_shoutout: has_existing }
  end
end
