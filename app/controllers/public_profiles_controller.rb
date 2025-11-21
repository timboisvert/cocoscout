class PublicProfilesController < ApplicationController
  skip_before_action :require_authentication

  def show
    key = params[:public_key]

    # Try to find a person with this key
    @person = Person.find_by(public_key: key)

    # If not found, check if it's an old key that was changed
    unless @person
      @person = Person.where("old_keys LIKE ?", "%#{key}%").first
      if @person
        # Redirect to new key
        redirect_to public_profile_path(@person.public_key), status: :moved_permanently
        return
      end
    end

    # Try to find a group with this key
    @group = Group.find_by(public_key: key) unless @person

    # If not found, check if it's an old group key that was changed
    unless @group || @person
      @group = Group.where("old_keys LIKE ?", "%#{key}%").first
      if @group
        # Redirect to new key
        redirect_to public_profile_path(@group.public_key), status: :moved_permanently
        return
      end
    end

    # If neither found, 404
    unless @person || @group
      render file: "#{Rails.root}/public/404.html", status: :not_found, layout: false
      return
    end

    # Set @entity for the views
    @entity = @person || @group

    # Render appropriate template
    if @person
      render "public_profiles/person"
    else
      render "public_profiles/group"
    end
  end
end
