class PublicProfilesController < ApplicationController
  skip_before_action :require_authentication
  before_action :resume_session_if_present
  before_action :find_entity, only: [ :show, :shoutouts ]

  def show
    # Check if profile is enabled
    if @person && !@person.public_profile_enabled
      render "public_profiles/not_found", status: :not_found
      return
    elsif @group && !@group.public_profile_enabled
      render "public_profiles/not_found", status: :not_found
      return
    end

    # Render appropriate template
    if @person
      render "public_profiles/person"
    else
      render "public_profiles/group"
    end
  end

  def shoutouts
    # Only show current versions (not replaced shoutouts)
    @shoutouts = @entity.received_shoutouts
      .left_joins(:replacement)
      .where(replacement: { id: nil })
      .newest_first
      .includes(:author)

    # Check if current user has already given this person a shoutout
    if Current.user&.person
      @has_given_shoutout = Current.user.person.given_shoutouts
        .where(shoutee: @entity)
        .where(id: Shoutout.left_joins(:replacement).where(replacement: { id: nil }).select(:id))
        .exists?
    end
  end

  private

  def find_entity
    key = params[:public_key]

    # Try to find a person with this key
    @person = Person.find_by(public_key: key)

    # If not found, check if it's an old key that was changed
    unless @person
      Person.where.not(old_keys: nil).find_each do |person|
        old_keys_array = JSON.parse(person.old_keys) rescue []
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
        old_keys_array = JSON.parse(group.old_keys) rescue []
        if old_keys_array.include?(key)
          @group = group
          # Redirect to new key
          redirect_to public_profile_path(@group.public_key), status: :moved_permanently
          return
        end
      end
    end

    # If neither found, 404
    unless @person || @group
      render "public_profiles/not_found", status: :not_found
      return
    end

    # Set @entity for the views
    @entity = @person || @group
  end

  def resume_session_if_present
    resume_session
  end
end
