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
        old_attrs = @mic.attributes.slice(*allowed_keys)
        @mic.assign_attributes(mic_params)
        @mic.save!
        @mic.attributes.slice(*allowed_keys).each do |k, v|
          next if old_attrs[k].to_s == v.to_s
          @mic.mic_edits.create!(editor_user_id: current_user.id, source: :producer,
                                  field: k, old_value: old_attrs[k].to_s, new_value: v.to_s)
        end
      end
      redirect_to mics_producer_mic_path(@mic.slug), notice: "Saved."
    rescue ActiveRecord::RecordInvalid => e
      flash.now[:alert] = e.message
      render :show, status: :unprocessable_content
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
      return false unless current_user
      return true if current_user.respond_to?(:superadmin?) && current_user.superadmin?
      @mic.mic_producers.where(user_id: current_user.id).exists?
    end

    def allowed_keys
      %w[name format day_of_week starts_local_time recurrence_pattern recurrence_interval recurrence_nth_week recurrence_day_of_month recurrence_anchor_date canceled_until signup_method bucket_draw signup_url signup_opens_at_text blurb spot_length_minutes signup_cap cost drink_minimum_amount_cents cover_amount_cents min_age host_summary]
    end

    def mic_params
      params.require(:mic).permit(*allowed_keys.map(&:to_sym))
    end
  end
end
