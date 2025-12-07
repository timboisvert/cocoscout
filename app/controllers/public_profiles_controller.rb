# frozen_string_literal: true

class PublicProfilesController < ApplicationController
  skip_before_action :require_authentication
  before_action :resume_session_if_present
  before_action :find_entity, only: %i[show shoutouts]
  before_action :find_production, only: %i[production_show]

  def show
    # Check if profile is enabled
    if @person && !@person.public_profile_enabled
      render "public_profiles/not_found", status: :not_found
      return
    elsif @group && !@group.public_profile_enabled
      render "public_profiles/not_found", status: :not_found
      return
    elsif @production && !@production.public_profile_enabled
      render "public_profiles/not_found", status: :not_found
      return
    end

    # Render appropriate template with HTTP caching
    if @person
      # HTTP caching for person profile
      fresh_when etag: @person.cache_key_for(:person_profile),
                 last_modified: @person.updated_at,
                 public: true
      return if request.fresh?(response)

      render "public_profiles/person"
    elsif @group
      # HTTP caching for group profile
      fresh_when etag: @group.cache_key_for(:group_profile),
                 last_modified: @group.updated_at,
                 public: true
      return if request.fresh?(response)

      render "public_profiles/group"
    else
      # HTTP caching for production profile
      fresh_when etag: @production.public_profile_etag,
                 last_modified: @production.public_profile_last_modified,
                 public: true
      return if request.fresh?(response)

      # Production - get publicly visible upcoming shows (only if feature enabled)
      if @production.show_upcoming_events?
        @upcoming_shows = @production.publicly_visible_upcoming_shows.sort_by(&:date_and_time)
      else
        @upcoming_shows = []
      end

      # Get cast members if feature enabled
      if @production.show_cast_members?
        @cast_members = @production.public_cast_members
      else
        @cast_members = []
      end

      render "public_profiles/production"
    end
  end

  def production_show
    @show = @production.shows.find_by(id: params[:show_id])

    # Show not found or not publicly visible
    unless @show && @show.public_profile_visible? && !@show.canceled
      render "public_profiles/not_found", status: :not_found
      return
    end

    # HTTP caching for show page
    fresh_when etag: @show.public_show_etag,
               last_modified: @show.updated_at,
               public: true
    return if request.fresh?(response)

    render "public_profiles/production_show"
  end

  def shoutouts
    # Only show current versions (not replaced shoutouts)
    @shoutouts = @entity.received_shoutouts
                        .left_joins(:replacement)
                        .where(replacement: { id: nil })
                        .newest_first
                        .includes(:author)

    # Check if current user has already given this person a shoutout
    return unless Current.user&.person

    @has_given_shoutout = Current.user.person.given_shoutouts
                                 .where(shoutee: @entity)
                                 .where(id: Shoutout.left_joins(:replacement).where(replacement: { id: nil }).select(:id))
                                 .exists?
  end

  private

  def find_entity
    key = params[:public_key]

    # Try to find a person with this key
    @person = Person.find_by(public_key: key)

    # If not found, check if it's an old key that was changed
    unless @person
      Person.where.not(old_keys: nil).find_each do |person|
        old_keys_array = begin
          JSON.parse(person.old_keys)
        rescue StandardError
          []
        end
        if old_keys_array.include?(key)
          @person = person
          # Redirect to new key
          redirect_to public_profile_path(@person.public_key), status: :moved_permanently
          return
        end
      end
    end

    # Try to find a group with this key
    @group = Group.find_by(public_key: key) unless @person

    # If not found, check if it's an old group key that was changed
    unless @group || @person
      Group.where.not(old_keys: nil).find_each do |group|
        old_keys_array = begin
          JSON.parse(group.old_keys)
        rescue StandardError
          []
        end
        if old_keys_array.include?(key)
          @group = group
          # Redirect to new key
          redirect_to public_profile_path(@group.public_key), status: :moved_permanently
          return
        end
      end
    end

    # Try to find a production with this key
    @production = Production.find_by(public_key: key) unless @person || @group

    # If not found, check if it's an old production key that was changed
    unless @production || @group || @person
      Production.where.not(old_keys: nil).find_each do |production|
        old_keys_array = begin
          JSON.parse(production.old_keys)
        rescue StandardError
          []
        end
        if old_keys_array.include?(key)
          @production = production
          # Redirect to new key
          redirect_to public_profile_path(@production.public_key), status: :moved_permanently
          return
        end
      end
    end

    # If none found, 404
    unless @person || @group || @production
      render "public_profiles/not_found", status: :not_found
      return
    end

    # Set @entity for the views (for person/group, production uses @production directly)
    @entity = @person || @group
  end

  def find_production
    key = params[:public_key]

    @production = Production.find_by(public_key: key)

    # If not found, check if it's an old key that was changed
    unless @production
      Production.where.not(old_keys: nil).find_each do |production|
        old_keys_array = begin
          JSON.parse(production.old_keys)
        rescue StandardError
          []
        end
        if old_keys_array.include?(key)
          @production = production
          # Redirect to new key with show_id
          redirect_to public_profile_show_path(@production.public_key, params[:show_id]), status: :moved_permanently
          return
        end
      end
    end

    # Production not found or not enabled
    unless @production && @production.public_profile_enabled
      render "public_profiles/not_found", status: :not_found
      nil
    end
  end

  def resume_session_if_present
    resume_session
  end
end
