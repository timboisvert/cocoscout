class ProfileController < ApplicationController
  before_action :set_person
  layout "profile", except: [ :preview ]

  def index
    # Edit mode - show profile edit form with left sidebar
  end

  def update
    if @person.update(person_params)
      respond_to do |format|
        format.turbo_stream do
          # Reload associations to ensure newly saved items are included
          @person.reload

          # Only reload sections that were actually updated
          streams = []

          if person_params[:profile_headshots_attributes].present?
            streams << turbo_stream.replace("headshots", partial: "profile/headshots_form")
          end

          if person_params[:profile_resumes_attributes].present?
            streams << turbo_stream.replace("resumes", partial: "profile/resumes_form_new")
          end

          if person_params[:profile_videos_attributes].present?
            streams << turbo_stream.replace("videos", partial: "shared/profile_videos_form_new")
          end

          if person_params[:training_credits_attributes].present?
            streams << turbo_stream.replace("training", partial: "profile/training_credits_form_new")
          end

          if person_params[:profile_skills_attributes].present?
            streams << turbo_stream.replace("skills", partial: "profile/skills_form_new")
          end

          if person_params[:performance_sections_attributes].present?
            streams << turbo_stream.replace("performance-history", partial: "profile/performance_credits_form_new")
          end

          # Always show success message
          streams << turbo_stream.update(
            "flash-messages",
            partial: "shared/flash",
            locals: { type: "success", message: "Saved" }
          )

          render turbo_stream: streams
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

  def update_visibility
    field = params[:field]
    value = params[:value] == "1"

    # Get current settings and merge the new value
    current_settings = @person.visibility_settings
    updated_settings = current_settings.merge(field => value)

    if @person.update(profile_visibility_settings: updated_settings.to_json)
      head :ok
    else
      head :unprocessable_entity
    end
  end

  def preview
    # Show profile as others see it (public view)
    @entity = @person
    render "public_profiles/person", layout: "application", locals: { entity: @person }
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

  def change_url
    # Show form to change public_key
  end

  def check_url_availability
    proposed_key = params[:public_key]&.strip&.downcase

    # Check cooldown period first
    settings = YAML.load_file(Rails.root.join("config", "profile_settings.yml"))
    cooldown_days = settings["url_change_cooldown_days"]

    if @person.public_key_changed_at && @person.public_key_changed_at > cooldown_days.days.ago
      render json: {
        available: false,
        message: "You changed your public URL too recently."
      }, status: :unprocessable_entity
      return
    end

    # Validate format
    unless proposed_key =~ /\A[a-z0-9][a-z0-9\-]{2,29}\z/
      render json: {
        available: false,
        message: "URL must be 3-30 characters: lowercase letters, numbers, and hyphens only"
      }, status: :unprocessable_entity
      return
    end

    # Check if it's the same as current
    if proposed_key == @person.public_key
      render json: {
        available: false,
        message: "This is already your current URL"
      }, status: :unprocessable_entity
      return
    end

    # Check if reserved
    reserved = YAML.safe_load_file(
      Rails.root.join("config", "reserved_public_keys.yml"),
      permitted_classes: [],
      permitted_symbols: [],
      aliases: true
    )
    if reserved.include?(proposed_key)
      render json: {
        available: false,
        message: "This URL is reserved for CocoScout system pages"
      }, status: :unprocessable_entity
      return
    end

    # Check if taken by another person or group
    if Person.where(public_key: proposed_key).where.not(id: @person.id).exists? ||
       Group.where(public_key: proposed_key).exists?
      render json: {
        available: false,
        message: "This URL is already taken"
      }, status: :unprocessable_entity
      return
    end

    # Available!
    render json: {
      available: true,
      message: "This URL is available!"
    }
  end

  def update_url
    new_key = params[:person][:public_key]&.strip&.downcase

    # Check cooldown period from config
    settings = YAML.load_file(Rails.root.join("config", "profile_settings.yml"))
    cooldown_days = settings["url_change_cooldown_days"]

    if @person.public_key_changed_at && @person.public_key_changed_at > cooldown_days.days.ago
      flash[:error] = "You changed your public URL too recently."
      redirect_to profile_path
      return
    end

    if @person.update(public_key: new_key)
      redirect_to profile_path, notice: "Your profile URL has been updated successfully."
    else
      flash[:error] = @person.errors.full_messages.join(", ")
      redirect_to profile_path
    end
  end

  def change_email
    # Show form to change email
  end

  def update_email
    new_email = params[:person][:email]&.strip&.downcase

    # Check if 30 days have passed since last change
    if @person.last_email_changed_at && @person.last_email_changed_at > 30.days.ago
      days_remaining = (30 - (Time.current - @person.last_email_changed_at).to_i / 1.day).ceil
      flash[:error] = "You can only change your email once every 30 days. #{days_remaining} days remaining."
      render :change_email, status: :unprocessable_entity
      return
    end

    if @person.update(email: new_email, last_email_changed_at: Time.current)
      redirect_to profile_path, notice: "Your email has been updated successfully."
    else
      flash.now[:error] = @person.errors.full_messages.join(", ")
      render :change_email, status: :unprocessable_entity
    end
  end

  private

  def set_person
    @person = Current.user.person
  end

  def person_params
    permitted_params = params.require(:person).permit(
      :name, :email, :phone, :pronouns, :resume, :headshot, :hide_contact_info,
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
        :id, :institution, :program,
        :year_start, :year_end, :notes, :position, :_destroy
      ],
      profile_skills_attributes: {}
    )

    # Manually permit the nested profile_skills_attributes hash
    if params[:person][:profile_skills_attributes].present?
      permitted_params[:profile_skills_attributes] = params[:person][:profile_skills_attributes].permit!
    end

    # Filter out profile_skills with blank skill_name (unchecked skills)
    # BUT keep skills with an ID (existing skills being updated/deleted)
    if permitted_params[:profile_skills_attributes].present?
      permitted_params[:profile_skills_attributes] = permitted_params[:profile_skills_attributes].select do |_key, attrs|
        # Keep if it has an ID (existing skill)
        has_id = attrs[:id].present? || attrs["id"].present?
        # OR if it has a skill_name (new skill being added)
        has_skill_name = (attrs[:skill_name] || attrs["skill_name"]).present?

        has_id || has_skill_name
      end
    end

    permitted_params
  end
end
