# frozen_string_literal: true

class ProfileController < ApplicationController
  before_action :set_person
  layout "profile", except: %i[preview welcome]
  before_action :hide_sidebar_on_welcome, only: [ :welcome ]

  def index
    # Redirect to welcome screen if this is their first time
    return unless @person.profile_welcomed_at.nil?

    redirect_to profile_welcome_path
    nil

    # Edit mode - show profile edit form with left sidebar
  end

  def welcome
    # Show welcome screen (don't mark as welcomed until they proceed)
  end

  def dismiss_welcome
    @person.update(profile_welcomed_at: Time.current)
    redirect_to profile_path
  end

  def mark_welcomed
    @person.update(profile_welcomed_at: Time.current)
    head :ok
  end

  def update
    # Handle virtual attribute conversion
    @person.show_contact_info = person_params[:show_contact_info] if person_params[:show_contact_info].present?

    if @person.update(person_params.except(:show_contact_info))
      respond_to do |format|
        format.json do
          # For JSON requests (from modal), return the uploaded file info
          response_data = { success: true }

          if person_params[:profile_resumes_attributes].present?
            resume = @person.profile_resumes.order(created_at: :desc).first
            if resume&.file&.attached?
              response_data[:resume] = {
                id: resume.id,
                filename: resume.file.filename.to_s,
                content_type: resume.file.content_type,
                url: rails_blob_path(resume.file, only_path: true)
              }

              # Generate preview URL if possible
              if resume.file.content_type == "application/pdf" && resume.file.representable?
                response_data[:resume][:preview_url] =
                  rails_representation_url(resume.file.representation(resize_to_limit: [ 300, 400 ]))
              elsif resume.file.content_type.start_with?("image/")
                response_data[:resume][:preview_url] =
                  rails_blob_path(resume.file.variant(resize_to_fill: [ 300, 400 ]), only_path: true)
              end
            end
          end

          if person_params[:profile_headshots_attributes].present?
            headshot = @person.profile_headshots.order(created_at: :desc).first
            if headshot&.image&.attached?
              response_data[:headshot] = {
                id: headshot.id,
                filename: headshot.image.filename.to_s,
                preview_url: rails_blob_path(headshot.image.variant(resize_to_fill: [ 300, 400 ]), only_path: true)
              }
            end
          end

          render json: response_data
        end
        format.turbo_stream do
          # Reload associations to ensure newly saved items are included
          @person.reload

          # Only reload sections that were actually updated
          streams = []

          if person_params[:profile_headshots_attributes].present?
            streams << turbo_stream.replace("headshots", partial: "shared/profiles/headshots",
                                                         locals: { entity: @person })
          end

          if person_params[:profile_resumes_attributes].present?
            streams << turbo_stream.replace("resumes", partial: "shared/profiles/resumes", locals: { entity: @person })
          end

          if person_params[:profile_videos_attributes].present?
            streams << turbo_stream.replace("videos", partial: "shared/profiles/videos", locals: { entity: @person })
          end

          if person_params[:training_credits_attributes].present?
            streams << turbo_stream.replace("training", partial: "shared/profiles/training_credits",
                                                        locals: { entity: @person })
          end

          if person_params[:profile_skills_attributes].present?
            streams << turbo_stream.replace("skills", partial: "shared/profiles/skills", locals: { entity: @person })
          end

          if person_params[:performance_sections_attributes].present?
            streams << turbo_stream.replace("performance-history", partial: "shared/profiles/performance_credits",
                                                                   locals: { entity: @person })
          end

          if person_params[:socials_attributes].present?
            streams << turbo_stream.replace("social-media", partial: "shared/profiles/social_media",
                                                            locals: { entity: @person })
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
        format.json do
          render json: { success: false, errors: @person.errors.full_messages }, status: :unprocessable_entity
        end
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

    # Whitelist of allowed visibility fields
    allowed_fields = %w[
      bio_visible headshots_visible resumes_visible social_media_visible
      videos_visible performance_credits_visible training_credits_visible profile_skills_visible
    ]

    unless allowed_fields.include?(field)
      head :unprocessable_entity
      return
    end

    # Update the specific visibility field
    if @person.update(field => value)
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

    Rails.logger.error "Validation errors: #{headshot.errors.full_messages.join(', ')}" unless result

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
    proposed_key = params[:public_key]
    result = PublicKeyService.validate(proposed_key, entity_type: :person, exclude_entity: @person)

    status = result[:available] ? :ok : :unprocessable_entity
    render json: result, status: status
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
      redirect_to profile_path,
                  notice: "You can only change your email once every 30 days. #{days_remaining} days remaining."
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

  def hide_sidebar_on_welcome
    @hide_sidebar = true
  end

  def person_params
    permitted_params = params.require(:person).permit(
      :name, :email, :phone, :pronouns, :resume, :headshot, :hide_contact_info, :show_contact_info, :bio, :public_profile_enabled,
      profile_visibility_settings: {},
      socials_attributes: %i[id platform handle name _destroy],
      profile_headshots_attributes: %i[id category is_primary position image _destroy],
      profile_resumes_attributes: %i[id name position file _destroy],
      profile_videos_attributes: %i[id title url position _destroy],
      performance_sections_attributes: [
        :id, :name, :position, :_destroy,
        { performance_credits_attributes: %i[
          id section_name title location role
          year_start year_end ongoing notes link_url position _destroy
        ] }
      ],
      training_credits_attributes: %i[
        id institution program
        year_start year_end ongoing notes position _destroy
      ]
    )

    # Manually permit the nested profile_skills_attributes hash with specific keys
    if params[:person][:profile_skills_attributes].present?
      permitted_skills = {}
      params[:person][:profile_skills_attributes].each do |key, attrs|
        permitted_skills[key] = attrs.permit(:id, :category, :skill_name, :_destroy)
      end
      permitted_params[:profile_skills_attributes] = permitted_skills
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
        render json: { error: "You're the only owner. Transfer ownership before leaving." },
               status: :unprocessable_entity
        return
      end
    end

    membership.destroy!
    render json: { success: true, message: "Successfully left group" }
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Membership not found" }, status: :not_found
  end
end
