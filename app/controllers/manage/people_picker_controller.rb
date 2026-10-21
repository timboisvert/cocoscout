# frozen_string_literal: true

module Manage
  # The shared People Picker's search (V1.1 plan §5): the one place every
  # "pick a person" sheet asks, scoped to what the page is picking for.
  #   q              what was typed; two characters or more, or nothing with
  #                  list=pool
  #   scope          "people" (the organization's people, the default),
  #                  "users" (only those with an account, for team pages),
  #                  "members" (people and groups)
  #   list           "pool": with nothing typed, the production's talent pool,
  #                  available for the show first (casting pages)
  #   outside        "1" adds people on CocoScout outside the organization
  #                  (PersonSearch: by name, profile key or their exact email;
  #                  their email never shows unless it's what was typed)
  #   invite         "1" offers to invite a typed email nobody has
  #   guest          "1" offers to add a guest by name (and email) instead
  #   production_id  its talent pool's members wear "In the talent pool"; on
  #                  the users scope its team is "On the team" and not pickable
  #   talent_pool_id that pool's members are "In the pool" and not pickable
  #   show_id        each person's availability for that show (and its linked
  #                  shows) as a badge; who's in the show already is
  #                  "Already in this show" and not pickable, or a badge when
  #                  in_show=badge (an act-based night casts one person twice)
  #   role_id        a restricted role: those not approved for it wear
  #                  "Not approved for this role" (the page asks before
  #                  assigning anyway)
  #   exclude        ids (or Type_id keys) already picked or added: "Already
  #                  added" (or exclude_label), not pickable
  #   invited        ids already invited: "Already invited", not pickable
  class PeoplePickerController < Manage::ManageController
    before_action :set_production_scope
    before_action :ensure_user_is_manager

    SCOPES = %w[people users members].freeze
    HEADSHOTS = { profile_headshots: { image_attachment: :blob } }.freeze

    def search
      q = params[:q].to_s.strip
      scope = params[:scope].presence_in(SCOPES) || "people"
      listing = q.length < 2 && params[:list] == "pool" && @production.present?
      locals = { query: q, people: [], groups: [], outside: [], already: {}, badges: Hash.new { |h, k| h[k] = [] }, ineligible: Set.new,
                 invite_email: nil, invite_name: params[:invite_name] == "1", guest: params[:guest] == "1", listing: listing }

      if q.length >= 2 || listing
        org = Current.organization
        people, groups = listing ? pool_members(scope) : search_members(org, q, scope)

        already = {}
        exclude_label = params[:exclude_label].presence || "Already added"
        Array(params[:exclude]).each { |id| already[key_for(id)] = exclude_label }
        Array(params[:invited]).each { |id| already[key_for(id)] = "Already invited" }
        if (pool = talent_pool)
          pool.talent_pool_memberships.pluck(:member_type, :member_id).each { |type, id| already["#{type}_#{id}"] = "In the pool" }
        end
        badges = locals[:badges]
        if @production
          if scope == "users"
            team_user_ids = @production.production_permissions.pluck(:user_id).to_set
            people.each { |p| already["Person_#{p.id}"] = "On the team" if team_user_ids.include?(p.user_id) }
          elsif !listing && (effective = @production.effective_talent_pool)
            effective.talent_pool_memberships.where(member_type: "Person").pluck(:member_id).to_set
                     .each { |id| badges["Person_#{id}"] << "In the talent pool" }
          end
        end

        show = @production && params[:show_id].present? ? @production.shows.find_by(id: params[:show_id]) : nil
        if show
          members = people + groups
          availability_badges(show, members).each { |key, badge| badges[key] << badge }
          in_show = ShowPersonRoleAssignment.where(show: show).pluck(:assignable_type, :assignable_id).map { |t, id| "#{t}_#{id}" }.to_set
          members.each do |m|
            key = "#{m.class.name}_#{m.id}"
            next unless in_show.include?(key)

            if params[:in_show] == "badge" then badges[key] << "Already in this show"
            else already[key] ||= "Already in this show"
            end
          end
          if params[:role_id].present? && (role = show.available_roles.find_by(id: params[:role_id])) && role.restricted?
            members.each do |m|
              next if role.eligible?(m)

              locals[:ineligible] << "#{m.class.name}_#{m.id}"
              badges["#{m.class.name}_#{m.id}"] << "Not approved for this role"
            end
          end
          if listing
            rank = ->(m) { badges["#{m.class.name}_#{m.id}"].find { |b| b.start_with?("Available", "Unavailable") }.to_s }
            order = { "Available" => 0, "" => 2, "Unavailable" => 3 }
            people.sort_by! { |m| [ order.fetch(rank.call(m).split(" ").first.to_s, 1), m.name.to_s.downcase ] }
            groups.sort_by! { |m| [ order.fetch(rank.call(m).split(" ").first.to_s, 1), m.name.to_s.downcase ] }
          end
        end

        outside = []
        if params[:outside] == "1" && !listing
          outside = PersonSearch.outside(q).where.not(id: org.people.select(:id)).includes(HEADSHOTS).limit(10).to_a
          outside.select! { |p| p.user_id.present? } if scope == "users"
        end

        if params[:invite] == "1" && q.include?("@") && (people + outside).none? { |p| p.email&.casecmp?(q) }
          locals[:invite_email] = q
        end
        locals.merge!(people: people, groups: groups, outside: outside, already: already)
      end

      render partial: "shared/people_picker/results", locals: locals
    end

    private

    # A production's picker checks the production's managers; the rest the
    # organization's.
    def set_production_scope
      return if params[:production_id].blank?

      @production = Current.organization.productions.find(params[:production_id])
    end

    def talent_pool
      return nil if params[:talent_pool_id].blank?

      TalentPool.joins(:production).where(productions: { organization_id: Current.organization.id }).find_by(id: params[:talent_pool_id])
    end

    def search_members(org, q, scope)
      like = "%#{Person.sanitize_sql_like(q)}%"
      people = org.people.where("people.name ILIKE :like OR people.email ILIKE :like", like: like).includes(HEADSHOTS).order(:name).limit(20).to_a
      people.select! { |p| p.user_id.present? } if scope == "users"
      groups = scope == "members" ? org.groups.where("groups.name ILIKE ?", like).order(:name).limit(10).to_a : []
      [ people, groups ]
    end

    # The production's talent pool, for a casting page's list before a search.
    def pool_members(scope)
      pool = @production.effective_talent_pool
      return [ [], [] ] unless pool

      people = pool.people.includes(HEADSHOTS).order(:name).limit(60).to_a
      groups = scope == "members" ? pool.groups.order(:name).limit(20).to_a : []
      [ people, groups ]
    end

    # "Available" or "Unavailable" for the show; on a linked event, how many
    # of its dates they're available for.
    def availability_badges(show, members)
      shows = [ show ] + show.linked_shows.to_a
      answers = ShowAvailability.where(show_id: shows.map(&:id))
                                .where(available_entity_type: members.map { |m| m.class.name }.uniq)
                                .group_by { |a| "#{a.available_entity_type}_#{a.available_entity_id}" }
      members.each_with_object({}) do |m, badges|
        key = "#{m.class.name}_#{m.id}"
        mine = answers[key] || []
        here = mine.find { |a| a.show_id == show.id }
        if shows.size > 1
          available = mine.count { |a| a.status == "available" }
          badges[key] =
            if available == shows.size then "Available"
            elsif available.positive? then "Available #{available} of #{shows.size} dates"
            elsif here&.status == "unavailable" then "Unavailable"
            end
        elsif here&.status.in?(%w[available unavailable])
          badges[key] = here.status.capitalize
        end
        badges.delete(key) if badges[key].nil?
      end
    end

    def key_for(id)
      id.to_s.include?("_") ? id.to_s : "Person_#{id.to_i}"
    end
  end
end
