# frozen_string_literal: true

module Manage
  # The shared People Picker's search (V1.1 plan §5): the one place every
  # "pick a person" sheet asks, scoped to what the page is picking for.
  #   q              what was typed; two characters or more
  #   scope          "people" (the organization's people, the default),
  #                  "users" (only those with an account, for team pages),
  #                  "members" (people and groups)
  #   outside        "1" adds people on CocoScout outside the organization
  #                  (PersonSearch: by name, profile key or their exact email;
  #                  their email never shows unless it's what was typed)
  #   invite         "1" offers to invite a typed email nobody has
  #   production_id  its talent pool's members wear "In the talent pool"; on
  #                  the users scope its team is "On the team" and not pickable
  #   talent_pool_id that pool's members are "In the pool" and not pickable
  #   show_id        each person's availability for that show, as a badge
  #   exclude        ids already picked or added: "Already added", not pickable
  class PeoplePickerController < Manage::ManageController
    before_action :set_production_scope
    before_action :ensure_user_is_manager

    SCOPES = %w[people users members].freeze

    def search
      q = params[:q].to_s.strip
      scope = params[:scope].presence_in(SCOPES) || "people"
      locals = { query: q, people: [], groups: [], outside: [], already: {}, badges: {}, availability: {},
                 invite_email: nil, invite_name: params[:invite_name] == "1" }

      if q.length >= 2
        org = Current.organization
        like = "%#{Person.sanitize_sql_like(q)}%"
        people = org.people.where("people.name ILIKE :like OR people.email ILIKE :like", like: like)
                    .includes(profile_headshots: { image_attachment: :blob }).order(:name).limit(20).to_a
        people.select! { |p| p.user_id.present? } if scope == "users"
        groups = scope == "members" ? org.groups.where("groups.name ILIKE ?", like).order(:name).limit(10).to_a : []

        already = {}
        Array(params[:exclude]).map(&:to_i).each { |id| already["Person_#{id}"] = "Already added" }
        if (pool = talent_pool)
          pool.talent_pool_memberships.pluck(:member_type, :member_id).each { |type, id| already["#{type}_#{id}"] = "In the pool" }
        end
        badges = {}
        if @production
          if scope == "users"
            team_user_ids = @production.production_permissions.pluck(:user_id).to_set
            people.each { |p| already["Person_#{p.id}"] = "On the team" if team_user_ids.include?(p.user_id) }
          elsif (effective = @production.effective_talent_pool)
            effective.talent_pool_memberships.where(member_type: "Person").pluck(:member_id).to_set
                     .each { |id| badges["Person_#{id}"] = "In the talent pool" }
          end
        end
        availability = {}
        if @production && params[:show_id].present? && (show = @production.shows.find_by(id: params[:show_id]))
          ShowAvailability.where(show: show, available_entity_type: "Person", available_entity_id: people.map(&:id))
                          .each { |a| availability[a.available_entity_id] = a.status.to_s }
        end

        outside = []
        if params[:outside] == "1"
          outside = PersonSearch.outside(q).where.not(id: org.people.select(:id))
                                .includes(profile_headshots: { image_attachment: :blob }).limit(10).to_a
          outside.select! { |p| p.user_id.present? } if scope == "users"
        end

        if params[:invite] == "1" && q.include?("@") && (people + outside).none? { |p| p.email&.casecmp?(q) }
          locals[:invite_email] = q
        end
        locals.merge!(people: people, groups: groups, outside: outside, already: already, badges: badges, availability: availability)
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
  end
end
