class ProfileController < ApplicationController
  before_action :set_person
  layout "profile"

  def index
    # Edit mode - show profile edit form with left sidebar
  end

  def update
    if @person.update(person_params)
      respond_to do |format|
        format.turbo_stream do
          # Reload the headshots section to show the newly saved headshot
          render turbo_stream: [
            turbo_stream.replace(
              "headshots",
              partial: "profile/headshots_form"
            ),
            turbo_stream.update(
              "flash-messages",
              partial: "shared/flash",
              locals: { type: "success", message: "Saved" }
            )
          ]
        end
        format.html { redirect_to profile_path, notice: "Profile was successfully updated" }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          error_message = @person.errors.full_messages.join(", ")
          render turbo_stream: turbo_stream.replace(
            "flash-messages",
            partial: "shared/flash",
            locals: { type: "error", message: error_message }
          )
        end
        format.html { render :index, status: :unprocessable_entity }
      end
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

  def set_primary_headshot
    headshot = @person.profile_headshots.find(params[:id])
    Rails.logger.info "Setting headshot #{headshot.id} as primary. Current is_primary: #{headshot.is_primary}"
    result = headshot.update(is_primary: true)
    Rails.logger.info "Update result: #{result}, is_primary after: #{headshot.is_primary}"

    if !result
      Rails.logger.error "Validation errors: #{headshot.errors.full_messages.join(', ')}"
    end

    # Reload to get fresh data
    @person.reload

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "headshots",
          partial: "profile/headshots_form"
        )
      end
      format.json { head :ok }
    end
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
      profile_resumes_attributes: [ :id, :name, :position, :file, :_destroy ],
      profile_videos_attributes: [ :id, :title, :url, :position, :_destroy ],
      performance_sections_attributes: [
        :id, :name, :position, :_destroy,
        performance_credits_attributes: [
          :id, :section_name, :title, :location, :role,
          :year_start, :year_end, :notes, :link_url, :position, :_destroy
        ]
      ],
      training_credits_attributes: [
        :id, :institution, :program, :location,
        :year_start, :year_end, :notes, :position, :_destroy
      ],
      profile_skills_attributes: [ :id, :category, :skill_name, :_destroy ]
    )
  end
end
