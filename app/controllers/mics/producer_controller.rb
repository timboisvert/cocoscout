# frozen_string_literal: true

module Mics
  class ProducerController < AuthedBaseController
    before_action :load_mic_and_authorize, except: [ :index ]

    # /mics/producer was the old producer-only index; My Mics rolled it
    # in. Anyone still hitting this URL gets sent to the unified page.
    def index
      redirect_to mics_my_path
    end

    def show
      @next_occurrences = @mic.next_occurrences(limit: 12)
      @co_producers = @mic.mic_producers.includes(:user)
      @recent_edits = @mic.mic_edits.order(created_at: :desc).limit(20)
      @pending_suggestions = @mic.mic_suggestions.status_pending.order(created_at: :desc)
    end

    def update
      Mic.transaction do
        old_attrs   = @mic.attributes.slice(*allowed_keys)
        old_access  = (@mic.accessibility || {}).dup
        @mic.assign_attributes(mic_params)
        apply_accessibility_params!
        @mic.save!
        @mic.attributes.slice(*allowed_keys).each do |k, v|
          next if old_attrs[k].to_s == v.to_s
          @mic.mic_edits.create!(editor_user_id: current_user.id, source: :producer,
                                  field: k, old_value: old_attrs[k].to_s, new_value: v.to_s)
        end
        if (@mic.accessibility || {}) != old_access
          @mic.mic_edits.create!(editor_user_id: current_user.id, source: :producer,
                                  field: "accessibility",
                                  old_value: old_access.to_json, new_value: @mic.accessibility.to_json)
        end
      end
      redirect_to mics_producer_mic_path(@mic.slug), notice: "Saved."
    rescue ActiveRecord::RecordInvalid => e
      flash.now[:alert] = e.message
      render :show, status: :unprocessable_content
    end

    # Permanent deletion — only the people who run the site/city, not the
    # producers themselves. Producers can leave the mic via remove_producer
    # on their own row; that's a different action.
    def destroy
      unless deletable_by?(current_user)
        head :forbidden
        return
      end

      name = @mic.name
      hub_slug = @mic.venue&.city_hub&.slug
      @mic.destroy!

      target = hub_slug ? mics_city_path(hub_slug) : mics_home_path
      redirect_to target, notice: "Deleted \"#{name}\"."
    end

    def verify
      @mic.update!(last_verified_at: Time.current, last_verified_by_user_id: current_user.id)
      @mic.mic_edits.create!(editor_user_id: current_user.id, source: :producer,
                              field: "last_verified_at", new_value: @mic.last_verified_at.to_s,
                              note: "Producer one-click verify")
      redirect_to mics_producer_mic_path(@mic.slug), notice: "Verified — thanks for keeping it fresh."
    end

    def post_status
      next_show_date = (params[:date].presence || Date.current.iso8601).to_s
      status_val     = params[:mic_status].to_s
      note           = params[:note].to_s.presence

      if @mic.production_id
        show = @mic.production.shows.where(event_type: :open_mic)
                   .where("date_and_time::date = ?", next_show_date).first
        show&.update!(mic_status: status_val)
      end

      # Source of truth for self-described mics — read by the public
      # detail page through `Mic#compute_occurrences`.
      occ = @mic.mic_occurrence_statuses.find_or_initialize_by(occurs_on: next_show_date)
      occ.assign_attributes(status: status_val, note: note, created_by_user_id: current_user.id)
      occ.save!

      @mic.mic_edits.create!(editor_user_id: current_user.id, source: :producer,
                              field: "mic_status", new_value: "#{next_show_date}=#{status_val}",
                              note: note || "One-off status post")
      redirect_to mics_producer_mic_path(@mic.slug), notice: "Status posted."
    end

    def cancel_date
      cancel_date = (params[:date].presence || Date.current.iso8601).to_s
      reason = params[:reason].to_s.presence

      if @mic.production_id
        show = @mic.production.shows.where(event_type: :open_mic)
                   .where("date_and_time::date = ?", cancel_date).first
        show&.update!(mic_status: "cancelled")
      end

      occ = @mic.mic_occurrence_statuses.find_or_initialize_by(occurs_on: cancel_date)
      occ.assign_attributes(status: :cancelled, note: reason, created_by_user_id: current_user.id)
      occ.save!

      @mic.mic_edits.create!(editor_user_id: current_user.id, source: :producer,
                              field: "mic_status", new_value: "#{cancel_date}=cancelled",
                              note: reason || "Producer cancelled this date")
      redirect_to mics_producer_mic_path(@mic.slug), notice: "Cancelled #{cancel_date}."
    end

    # JSON: look up a user by exact email match so the add-producer modal
    # can tell new vs existing without a page reload.
    def producer_lookup
      email = params[:email].to_s.strip.downcase
      if email.blank? || !email.match?(URI::MailTo::EMAIL_REGEXP)
        render json: { found: false, valid: false }
        return
      end

      user = User.find_by("LOWER(email_address) = ?", email)
      if user
        name = user.person&.name.presence
        already = @mic.mic_producers.exists?(user_id: user.id)
        render json: { found: true, valid: true, email: user.email_address, name: name, already_on_mic: already }
      else
        render json: { found: false, valid: true }
      end
    end

    def add_producer
      email = params[:email].to_s.strip.downcase
      name  = params[:name].to_s.strip.presence
      role  = MicProducer.roles.key?(params[:role].to_s) ? params[:role].to_s : "producer"

      unless email.match?(URI::MailTo::EMAIL_REGEXP)
        redirect_to mics_producer_mic_path(@mic.slug),
                    alert: "Please enter a valid email."
        return
      end

      user = User.find_by("LOWER(email_address) = ?", email)
      invited = false

      if user.blank?
        # Create a placeholder CocoScout account so we can attach the
        # MicProducer right away, then send the new user a password-set
        # link via the existing reset flow.
        user = User.create!(email_address: email, password: User.generate_secure_password)
        user.people.create!(name: name.presence || email.split("@").first.titleize)
        token = user.generate_token_for(:password_reset)
        AuthMailer.password(user, token).deliver_later
        invited = true
      end

      mp = @mic.mic_producers.find_or_initialize_by(user_id: user.id)
      mp.role = role
      mp.accepted_at ||= Time.current
      mp.save!

      if role == "producer" && @mic.lead_producer_user_id.blank?
        @mic.update!(lead_producer_user_id: user.id, claimed_at: @mic.claimed_at || Time.current)
      end

      @mic.mic_edits.create!(editor_user_id: current_user.id, source: :admin, field: "producer.add",
                              new_value: "#{user.email_address} as #{role.humanize}#{invited ? " (invited)" : ""}")

      notice = if invited
        "Invited #{user.email_address} to CocoScout and added them as #{role.humanize}."
      else
        "Added #{user.email_address} as #{role.humanize}."
      end
      redirect_to mics_producer_mic_path(@mic.slug), notice: notice
    end

    def remove_producer
      mp = @mic.mic_producers.find_by(id: params[:producer_id])
      if mp.nil?
        redirect_to mics_producer_mic_path(@mic.slug), alert: "That producer link isn't on this mic."
        return
      end

      user_label    = mp.user.email_address
      removed_self  = (mp.user_id == current_user.id)
      was_lead      = (@mic.lead_producer_user_id == mp.user_id)
      mp.destroy!

      if was_lead
        next_lead = @mic.mic_producers.order(:created_at).first
        @mic.update!(lead_producer_user_id: next_lead&.user_id)
      end

      # If that was the last runner, flip the mic back to unclaimed so the
      # public detail page shows "Claim this mic" again.
      if @mic.mic_producers.reload.empty?
        @mic.update!(claimed_at: nil, lead_producer_user_id: nil)
      end

      @mic.mic_edits.create!(editor_user_id: current_user.id, source: :admin, field: "producer.remove",
                              new_value: removed_self ? "#{user_label} (self)" : user_label)

      notice = if removed_self
        if @mic.mic_producers.empty?
          "You've stepped down. #{@mic.name} is now unclaimed."
        else
          "You've stepped down from #{@mic.name}. The remaining runners still manage it."
        end
      else
        "Removed #{user_label}."
      end

      target = removed_self ? mics_detail_path(@mic.slug) : mics_producer_mic_path(@mic.slug)
      redirect_to target, notice: notice
    end

    def set_lead_producer
      mp = @mic.mic_producers.find_by(id: params[:producer_id])
      if mp.nil?
        redirect_to mics_producer_mic_path(@mic.slug), alert: "That producer link isn't on this mic."
        return
      end

      @mic.update!(lead_producer_user_id: mp.user_id, claimed_at: @mic.claimed_at || Time.current)
      mp.update!(role: :producer) unless mp.role_producer?
      @mic.mic_edits.create!(editor_user_id: current_user.id, source: :admin, field: "producer.lead",
                              new_value: mp.user.email_address)
      redirect_to mics_producer_mic_path(@mic.slug), notice: "#{mp.user.email_address} is now the lead producer."
    end

    def approve_suggestion
      suggestion = @mic.mic_suggestions.find(params[:suggestion_id])
      suggestion.update!(status: :approved, decided_at: Time.current, adjudicator: current_user)
      @mic.mic_edits.create!(editor_user_id: current_user.id, source: :suggestion,
                              field: "suggestion", new_value: "approved",
                              note: suggestion.note.to_s.truncate(200))
      redirect_to mics_producer_mic_path(@mic.slug), notice: "Suggestion approved."
    end

    def reject_suggestion
      suggestion = @mic.mic_suggestions.find(params[:suggestion_id])
      suggestion.update!(status: :rejected, decided_at: Time.current, adjudicator: current_user)
      redirect_to mics_producer_mic_path(@mic.slug), notice: "Suggestion rejected."
    end

    def add_link
      link = @mic.mic_links.build(
        link_type: params[:link_type].to_s,
        url:       params[:url].to_s.strip,
        label:     params[:label].to_s.strip.presence
      )
      if link.save
        @mic.mic_edits.create!(editor_user_id: current_user.id, source: :producer,
                                field: "link.#{link.link_type}", new_value: link.url)
        redirect_to mics_producer_mic_path(@mic.slug), notice: "Link added."
      else
        redirect_to mics_producer_mic_path(@mic.slug), alert: link.errors.full_messages.to_sentence
      end
    end

    def remove_link
      link = @mic.mic_links.find_by(id: params[:link_id])
      link&.destroy
      redirect_to mics_producer_mic_path(@mic.slug), notice: "Link removed."
    end

    def invite
      email = params[:email].to_s.strip.downcase
      if email.blank?
        redirect_to mics_producer_mic_path(@mic.slug), alert: "Email required."
        return
      end
      user = User.find_by("LOWER(email_address) = ?", email)
      if user
        @mic.mic_producers.find_or_create_by!(user_id: user.id) { |mp| mp.role = :co_producer; mp.accepted_at = Time.current }
        redirect_to mics_producer_mic_path(@mic.slug), notice: "Added #{user.email_address} as co-producer."
      else
        redirect_to mics_producer_mic_path(@mic.slug), notice: "We'll email #{email} an invite to join CocoScout."
      end
    end

    private

    def load_mic_and_authorize
      @mic = Mic.find_by!(slug: params[:slug].to_s.downcase)
      head :forbidden unless authorized?
    rescue ActiveRecord::RecordNotFound
      render plain: "Not found", status: :not_found
    end

    def authorized?
      @mic.manageable_by?(current_user)
    end

    # Stricter than `manageable_by?` — producers shouldn't be able to
    # delete the mic entirely. Only superadmins and city captains can.
    def deletable_by?(user)
      return false unless user
      return true if user.respond_to?(:superadmin?) && user.superadmin?
      hub = @mic.venue&.city_hub
      hub.present? && hub.editor?(user)
    end
    helper_method :deletable_by?

    def allowed_keys
      %w[name format day_of_week starts_local_time recurrence_pattern recurrence_interval recurrence_nth_week recurrence_day_of_month recurrence_anchor_date canceled_until signup_method bucket_draw signup_url signup_opens_at_text blurb spot_length_minutes signup_cap cost drink_minimum_amount_cents cover_amount_cents min_age host_summary]
    end

    def mic_params
      params.require(:mic).permit(*allowed_keys.map(&:to_sym))
    end

    # Only apply accessibility changes when the form actually submitted the
    # nested hash — that way "Save basic info" doesn't wipe accessibility
    # set elsewhere, and other section forms don't reset it either.
    def apply_accessibility_params!
      nested = params.dig(:mic, :accessibility)
      return if nested.blank?
      access = (@mic.accessibility || {}).dup
      cast   = ActiveModel::Type::Boolean.new
      nested.to_unsafe_h.each do |key, raw|
        access[key.to_s] = cast.cast(raw) ? true : false
      end
      @mic.accessibility = access
    end
  end
end
