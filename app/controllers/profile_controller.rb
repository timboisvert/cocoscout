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
            streams << turbo_stream.replace("headshots", partial: "shared/profiles/headshots", locals: { entity: @person })
          end

          if person_params[:profile_resumes_attributes].present?
            streams << turbo_stream.replace("resumes", partial: "shared/profiles/resumes", locals: { entity: @person })
          end

          if person_params[:profile_videos_attributes].present?
            streams << turbo_stream.replace("videos", partial: "shared/profiles/videos", locals: { entity: @person })
          end

          if person_params[:training_credits_attributes].present?
            streams << turbo_stream.replace("training", partial: "shared/profiles/training_credits", locals: { entity: @person })
          end

          if person_params[:profile_skills_attributes].present?
            streams << turbo_stream.replace("skills", partial: "shared/profiles/skills", locals: { entity: @person })
          end

          if person_params[:performance_sections_attributes].present?
            streams << turbo_stream.replace("performance-history", partial: "shared/profiles/performance_credits", locals: { entity: @person })
          end

          if person_params[:socials_attributes].present?
            streams << turbo_stream.replace("social-media", partial: "shared/profiles/social_media", locals: { entity: @person })
          end

          # Always show success message using standard notice
          streams << turbo_stream.update(
            "notice-container",
            partial: "shared/notice",
            locals: { notice: "Profile saved" }
          )

          render turbo_stream: streams
        end
        format.html { redirect_to profile_path, notice: "Profile was successfully updated" }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          error_message = @person.errors.full_messages.join(", ")
          render turbo_stream: turbo_stream.update(
            "notice-container",
            partial: "shared/notice",
            locals: { notice: error_message }
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
          partial: "shared/profiles/headshots",
          locals: { entity: @person }
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
      redirect_to profile_path, notice: "You changed your public URL too recently."
      return
    end

    if @person.update(public_key: new_key)
      redirect_to profile_path, notice: "Your profile URL has been updated successfully."
    else
      redirect_to profile_path, notice: @person.errors.full_messages.join(", ")
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
      redirect_to profile_path, notice: "You can only change your email once every 30 days. #{days_remaining} days remaining."
      return
    end

    if @person.update(email: new_email, last_email_changed_at: Time.current)
      redirect_to profile_path, notice: "Your email has been updated successfully."
    else
      redirect_to profile_path, notice: @person.errors.full_messages.join(", ")
    end
  end

  private

  def set_person
    @person = Current.user.person
  end

  def person_params
    permitted_params = params.require(:person).permit(
      :name, :email, :phone, :pronouns, :resume, :headshot, :hide_contact_info, :show_contact_info, :bio,
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

  def search_groups
    query = params[:q]&.strip

    if query.blank? || query.length < 2
      render json: { groups: [] }
      return
    end

    # Search for groups, excluding ones the person is already a member of
    groups = Group.active
                  .where("LOWER(name) LIKE ?", "%#{query.downcase}%")
                  .where.not(id: @person.group_memberships.pluck(:group_id))
                  .limit(10)

    groups_data = groups.map do |group|
      {
        id: group.id,
        name: group.name,
        initials: group.initials,
        member_count: group.members.count,
        headshot_url: group.headshot.attached? ? url_for(group.headshot.variant(:thumb)) : nil
      }
    end

    render json: { groups: groups_data }
  end

  def join_group
    group = Group.find(params[:group_id])

    # Check if already a member
    if @person.group_memberships.exists?(group: group)
      render json: { error: "You're already a member of this group" }, status: :unprocessable_entity
      return
    end

    # Create membership with default view permission
    membership = @person.group_memberships.create!(
      group: group,
      permission_level: :view
    )

    render json: {
      success: true,
      membership_id: membership.id,
      message: "Successfully joined #{group.name}"
    }
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def leave_group
    membership = @person.group_memberships.find(params[:id])

    # Don't allow leaving if you're the only owner
    if membership.owner?
      owner_count = membership.group.group_memberships.where(permission_level: :owner).count
      if owner_count <= 1
        render json: { error: "You're the only owner. Transfer ownership before leaving." }, status: :unprocessable_entity
        return
      end
    end

    membership.destroy!
    render json: { success: true, message: "Successfully left group" }
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Membership not found" }, status: :not_found
  end
end
