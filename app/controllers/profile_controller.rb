class ProfileController < ApplicationController
  before_action :set_person
  layout "profile"

  def index
    # Edit mode - show profile edit form with left sidebar
  end

  def update
    if @person.update(person_params)
      redirect_to profile_path, notice: "Profile was successfully updated"
    else
      render :index, status: :unprocessable_entity
    end
  end

  def preview
    # Show profile as others see it (public view)
    render "public_profiles/person", layout: "application"
  end

  def public
    # Share page with copyable link and QR code
    @public_url = public_profile_url(@person.public_key)
  end

  private

  def set_person
    @person = Current.user.person
  end

  def person_params
    params.require(:person).permit(
      :name, :email, :pronouns, :resume, :headshot, :hide_contact_info,
      profile_visibility_settings: {},
      socials_attributes: [ :id, :platform, :handle, :_destroy ],
      profile_headshots_attributes: [ :id, :category, :is_primary, :position, :image, :_destroy ],
      profile_videos_attributes: [ :id, :title, :url, :position, :_destroy ],
      performance_credits_attributes: [
        :id, :section_name, :title, :venue, :location, :role,
        :year_start, :year_end, :notes, :link_url, :position, :_destroy
      ],
      training_credits_attributes: [
        :id, :institution, :program, :location,
        :year_start, :year_end, :notes, :position, :_destroy
      ],
      profile_skills_attributes: [ :id, :category, :skill_name, :_destroy ]
    )
  end
end
