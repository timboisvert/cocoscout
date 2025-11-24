class My::ProfileController < ApplicationController
  def index
  end

  def edit
    @person = Current.user.person
  end

  def update
    @person = Current.user.person
    if @person.update(person_params)
      redirect_to my_profile_path, notice: "Profile was successfully updated"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private
    def person_params
      params.require(:person).permit(
        :name, :email, :pronouns, :resume, :headshot, :hide_contact_info,
        profile_visibility_settings: {},
        socials_attributes: [ :id, :platform, :handle, :_destroy ],
        profile_headshots_attributes: [ :id, :category, :is_primary, :position, :image, :_destroy ],
        profile_videos_attributes: [ :id, :title, :url, :position, :_destroy ],
        performance_credits_attributes: [
          :id, :section_name, :title, :location, :role,
          :year_start, :year_end, :notes, :link_url, :position, :_destroy
        ],
        training_credits_attributes: [
          :id, :institution, :program,
          :year_start, :year_end, :notes, :position, :_destroy
        ],
        profile_skills_attributes: [ :id, :category, :skill_name, :_destroy ]
      )
    end
end
