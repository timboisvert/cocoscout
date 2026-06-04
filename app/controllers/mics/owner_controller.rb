# frozen_string_literal: true

module Mics
  class OwnerController < AuthedBaseController
    before_action :load_mic_and_authorize, except: [ :index ]

    # /mics/owner was the old owner-only index; My Mics rolled it
    # in. Anyone still hitting this URL gets sent to the unified page.
    def index
      redirect_to mics_my_path
    end

    def show
      @next_occurrences = @mic.next_occurrences(limit: 12)
      @co_owners = @mic.mic_owners.includes(:user)
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
          @mic.mic_edits.create!(editor_user_id: current_user.id, source: :owner,
                                  field: k, old_value: old_attrs[k].to_s, new_value: v.to_s)
        end
        if (@mic.accessibility || {}) != old_access
          @mic.mic_edits.create!(editor_user_id: current_user.id, source: :owner,
                                  field: "accessibility",
                                  old_value: old_access.to_json, new_value: @mic.accessibility.to_json)
        end
      end
      redirect_to mics_owner_mic_path(@mic.slug), notice: "Saved."
    rescue ActiveRecord::RecordInvalid => e
      flash.now[:alert] = e.message
      render :show, status: :unprocessable_content
    end

    # Permanent deletion — only the people who run the site/city, not the
    # owners themselves. Owners can leave the mic via remove_owner on
    # their own row; that's a different action.
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

    # Edit the *current* venue in place — name, street, neighborhood,
    # city, state, ZIP. This affects every Mic at this venue, not just
    # this one; the view warns the owner accordingly.
    def update_venue
      venue = @mic.venue
      old_attrs = venue.attributes.slice(*VENUE_FIELDS)
      venue.assign_attributes(venue_params)
      venue.save!

      venue.attributes.slice(*VENUE_FIELDS).each do |k, v|
        next if old_attrs[k].to_s == v.to_s
        @mic.mic_edits.create!(editor_user_id: current_user.id, source: :owner,
                                field: "venue.#{k}", old_value: old_attrs[k].to_s, new_value: v.to_s)
      end
      redirect_to mics_owner_mic_path(@mic.slug), notice: "Venue updated."
    rescue ActiveRecord::RecordInvalid => e
      redirect_to mics_owner_mic_path(@mic.slug), alert: "Couldn't save venue: #{e.message}"
    end

    # Re-point this Mic at a different Venue (find existing or create
    # new). Leaves the old Venue untouched in case other mics use it.
    def move_venue
      # If the find-or-add picker landed on an existing venue, the form
      # posts its id alongside the address fields — re-point straight
      # to that row. Otherwise fall back to find-or-initialize by
      # name+city+state and create a fresh venue.
      target =
        if params[:venue_id].present? && (existing = Venue.find_by(id: params[:venue_id]))
          existing
        else
          name  = params[:venue_name].to_s.strip
          city  = params[:venue_city].to_s.strip
          state = params[:venue_state].to_s.strip.upcase

          if name.blank? || city.blank? || state.blank?
            redirect_to mics_owner_mic_path(@mic.slug),
                        alert: "Need at least venue name, city, and state to move the mic."
            return
          end

          v = Venue.find_or_initialize_by(name: name, city: city, state: state)
          if v.new_record?
            v.address1     = params[:venue_address1].to_s.strip.presence
            v.neighborhood = params[:venue_neighborhood].to_s.strip.presence
            v.postal_code  = params[:venue_postal_code].to_s.strip.presence
            v.country    ||= "US"
            v.timezone   ||= @mic.venue&.timezone || "America/Chicago"
            v.city_hub   ||= @mic.venue&.city_hub
            v.save!
          end
          v
        end

      old_venue_id = @mic.venue_id
      old_label    = "#{@mic.venue.name} (#{@mic.venue.neighborhood_city})"
      @mic.update!(venue: target)

      @mic.mic_edits.create!(editor_user_id: current_user.id, source: :owner,
                              field: "venue_id",
                              old_value: old_venue_id.to_s, new_value: target.id.to_s,
                              note: "Moved from #{old_label} to #{target.name} (#{target.city}, #{target.state})")
      redirect_to mics_owner_mic_path(@mic.slug), notice: "Moved to #{target.name}."
    end

    def verify
      @mic.update!(last_verified_at: Time.current, last_verified_by_user_id: current_user.id)
      @mic.mic_edits.create!(editor_user_id: current_user.id, source: :owner,
                              field: "last_verified_at", new_value: @mic.last_verified_at.to_s,
                              note: "Owner one-click verify")
      redirect_to mics_owner_mic_path(@mic.slug), notice: "Verified — thanks for keeping it fresh."
    end

    def post_status
      next_show_date = (params[:date].presence || Date.current.iso8601).to_s
      status_val     = params[:mic_status].to_s
      note           = params[:note].to_s.presence
      clearing       = (status_val == "clear")

      if @mic.production_id
        show = @mic.production.shows.where(event_type: :open_mic)
                   .where("date_and_time::date = ?", next_show_date).first
        show&.update!(mic_status: clearing ? nil : status_val)
      end

      # Source of truth for self-described mics — read by the public
      # detail page through `Mic#compute_occurrences`.
      if clearing
        @mic.mic_occurrence_statuses.where(occurs_on: next_show_date).destroy_all
        @mic.mic_edits.create!(editor_user_id: current_user.id, source: :owner,
                                field: "mic_status", new_value: "#{next_show_date}=cleared",
                                note: "Cleared status for this date")
        redirect_to mics_owner_mic_path(@mic.slug), notice: "Status cleared for #{next_show_date}."
        return
      end

      occ = @mic.mic_occurrence_statuses.find_or_initialize_by(occurs_on: next_show_date)
      occ.assign_attributes(status: status_val, note: note, created_by_user_id: current_user.id)
      occ.save!

      @mic.mic_edits.create!(editor_user_id: current_user.id, source: :owner,
                              field: "mic_status", new_value: "#{next_show_date}=#{status_val}",
                              note: note || "One-off status post")
      redirect_to mics_owner_mic_path(@mic.slug), notice: "Status posted."
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

      @mic.mic_edits.create!(editor_user_id: current_user.id, source: :owner,
                              field: "mic_status", new_value: "#{cancel_date}=cancelled",
                              note: reason || "Owner cancelled this date")
      redirect_to mics_owner_mic_path(@mic.slug), notice: "Cancelled #{cancel_date}."
    end

    # JSON: look up a user by exact email match so the add-owner modal
    # can tell new vs existing without a page reload.
    def owner_lookup
      email = params[:email].to_s.strip.downcase
      if email.blank? || !email.match?(URI::MailTo::EMAIL_REGEXP)
        render json: { found: false, valid: false }
        return
      end

      user = User.find_by("LOWER(email_address) = ?", email)
      if user
        name = user.person&.name.presence
        already = @mic.mic_owners.exists?(user_id: user.id)
        render json: { found: true, valid: true, email: user.email_address, name: name, already_on_mic: already }
      else
        render json: { found: false, valid: true }
      end
    end

    def add_owner
      email = params[:email].to_s.strip.downcase
      name  = params[:name].to_s.strip.presence
      role  = MicOwner.roles.key?(params[:role].to_s) ? params[:role].to_s : "owner"

      unless email.match?(URI::MailTo::EMAIL_REGEXP)
        redirect_to mics_owner_mic_path(@mic.slug),
                    alert: "Please enter a valid email."
        return
      end

      user = User.find_by("LOWER(email_address) = ?", email)
      invited = false

      if user.blank?
        # Create a placeholder CocoScout account so we can attach the
        # MicOwner right away, then send the new user a password-set
        # link via the existing reset flow.
        user = User.create!(email_address: email, password: User.generate_secure_password)
        user.people.create!(name: name.presence || email.split("@").first.titleize)
        token = user.generate_token_for(:password_reset)
        AuthMailer.password(user, token).deliver_later
        invited = true
      end

      mp = @mic.mic_owners.find_or_initialize_by(user_id: user.id)
      mp.role = role
      mp.accepted_at ||= Time.current
      mp.save!

      if role == "owner" && @mic.lead_owner_user_id.blank?
        @mic.update!(lead_owner_user_id: user.id, claimed_at: @mic.claimed_at || Time.current)
      end

      role_label = humanize_role(role)
      @mic.mic_edits.create!(editor_user_id: current_user.id, source: :admin, field: "owner.add",
                              new_value: "#{user.email_address} as #{role_label}#{invited ? " (invited)" : ""}")

      notice = if invited
        "Invited #{user.email_address} to CocoScout and added them as #{role_label}."
      else
        "Added #{user.email_address} as #{role_label}."
      end
      redirect_to mics_owner_mic_path(@mic.slug), notice: notice
    end

    def remove_owner
      mp = @mic.mic_owners.find_by(id: params[:owner_id])
      if mp.nil?
        redirect_to mics_owner_mic_path(@mic.slug), alert: "That owner link isn't on this mic."
        return
      end

      user_label    = mp.user.email_address
      removed_self  = (mp.user_id == current_user.id)
      was_lead      = (@mic.lead_owner_user_id == mp.user_id)
      mp.destroy!

      if was_lead
        next_lead = @mic.mic_owners.order(:created_at).first
        @mic.update!(lead_owner_user_id: next_lead&.user_id)
      end

      # If that was the last owner, flip the mic back to unclaimed so the
      # public detail page shows "Claim this mic" again.
      if @mic.mic_owners.reload.empty?
        @mic.update!(claimed_at: nil, lead_owner_user_id: nil)
      end

      @mic.mic_edits.create!(editor_user_id: current_user.id, source: :admin, field: "owner.remove",
                              new_value: removed_self ? "#{user_label} (self)" : user_label)

      notice = if removed_self
        if @mic.mic_owners.empty?
          "You've stepped down. #{@mic.name} is now unclaimed."
        else
          "You've stepped down from #{@mic.name}. The remaining owners still manage it."
        end
      else
        "Removed #{user_label}."
      end

      target = removed_self ? mics_detail_path(@mic.slug) : mics_owner_mic_path(@mic.slug)
      redirect_to target, notice: notice
    end

    def set_lead_owner
      mp = @mic.mic_owners.find_by(id: params[:owner_id])
      if mp.nil?
        redirect_to mics_owner_mic_path(@mic.slug), alert: "That owner link isn't on this mic."
        return
      end

      @mic.update!(lead_owner_user_id: mp.user_id, claimed_at: @mic.claimed_at || Time.current)
      mp.update!(role: :owner) unless mp.role_owner?
      @mic.mic_edits.create!(editor_user_id: current_user.id, source: :admin, field: "owner.lead",
                              new_value: mp.user.email_address)
      redirect_to mics_owner_mic_path(@mic.slug), notice: "#{mp.user.email_address} is now the lead owner."
    end

    def approve_suggestion
      suggestion = @mic.mic_suggestions.find(params[:suggestion_id])
      suggestion.update!(status: :approved, decided_at: Time.current, adjudicator: current_user)
      @mic.mic_edits.create!(editor_user_id: current_user.id, source: :suggestion,
                              field: "suggestion", new_value: "approved",
                              note: suggestion.note.to_s.truncate(200))
      redirect_to mics_owner_mic_path(@mic.slug), notice: "Suggestion approved."
    end

    def reject_suggestion
      suggestion = @mic.mic_suggestions.find(params[:suggestion_id])
      suggestion.update!(status: :rejected, decided_at: Time.current, adjudicator: current_user)
      redirect_to mics_owner_mic_path(@mic.slug), notice: "Suggestion rejected."
    end

    def add_link
      link = @mic.mic_links.build(
        link_type: params[:link_type].to_s,
        url:       params[:url].to_s.strip,
        label:     params[:label].to_s.strip.presence
      )
      if link.save
        @mic.mic_edits.create!(editor_user_id: current_user.id, source: :owner,
                                field: "link.#{link.link_type}", new_value: link.url)
        redirect_to mics_owner_mic_path(@mic.slug), notice: "Link added."
      else
        redirect_to mics_owner_mic_path(@mic.slug), alert: link.errors.full_messages.to_sentence
      end
    end

    def remove_link
      link = @mic.mic_links.find_by(id: params[:link_id])
      link&.destroy
      redirect_to mics_owner_mic_path(@mic.slug), notice: "Link removed."
    end

    def invite
      email = params[:email].to_s.strip.downcase
      if email.blank?
        redirect_to mics_owner_mic_path(@mic.slug), alert: "Email required."
        return
      end
      user = User.find_by("LOWER(email_address) = ?", email)
      if user
        @mic.mic_owners.find_or_create_by!(user_id: user.id) { |mp| mp.role = :co_owner; mp.accepted_at = Time.current }
        redirect_to mics_owner_mic_path(@mic.slug), notice: "Added #{user.email_address} as co-owner."
      else
        redirect_to mics_owner_mic_path(@mic.slug), notice: "We'll email #{email} an invite to join CocoScout."
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

    # Stricter than `manageable_by?` — owners shouldn't be able to
    # delete the mic entirely. Only superadmins and city captains can.
    def deletable_by?(user)
      return false unless user
      return true if user.respond_to?(:superadmin?) && user.superadmin?
      hub = @mic.venue&.city_hub
      hub.present? && hub.editor?(user)
    end
    helper_method :deletable_by?

    VENUE_FIELDS = %w[name address1 neighborhood city state postal_code].freeze

    def venue_params
      params.require(:venue).permit(*VENUE_FIELDS.map(&:to_sym))
    end

    def allowed_keys
      base = %w[name format day_of_week starts_local_time recurrence_pattern recurrence_interval recurrence_nth_week recurrence_nth_weeks recurrence_day_of_month recurrence_anchor_date custom_dates paused pause_note canceled_until signup_method bucket_draw signup_url signup_opens_at_text signup_notes blurb spot_length_minutes signup_cap cost drink_minimum_amount_cents cover_amount_cents min_age host_summary]
      # Slug edits are admin-only. Regular owners shouldn't be able to
      # rename the URL out from under existing inbound links.
      base += [ "slug" ] if deletable_by?(current_user)
      base
    end

    def mic_params
      # Exclude the array column from the scalar permit list — strong
      # params would otherwise drop the array values as un-permitted.
      scalar_keys = allowed_keys.map(&:to_sym) - [ :recurrence_nth_weeks, :custom_dates ]
      perm = params.require(:mic).permit(*scalar_keys, recurrence_nth_weeks: [])

      # Custom dates ride in as a JSON string in `mic[custom_dates_json]`
      # (the Stimulus controller assembles it). Decode it into the array
      # of {date, time} hashes the model expects — `normalize_recurrence_fields`
      # will validate and sort.
      raw_json = params.dig(:mic, :custom_dates_json)
      if raw_json.is_a?(String)
        decoded = JSON.parse(raw_json) rescue nil
        perm[:custom_dates] = Array(decoded) if decoded.is_a?(Array)
      end
      # Slug — normalize what the admin typed so we don't store dirty
      # values. Empty submitted slug is dropped so the existing slug
      # isn't overwritten with "".
      if perm[:slug].present?
        cleaned = perm[:slug].to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/^-+|-+$/, "")
        perm[:slug] = cleaned.presence || perm.delete(:slug)
      end
      perm
    end

    # Only apply accessibility changes when the form actually submitted the
    # nested hash — that way "Save basic info" doesn't wipe accessibility
    # set elsewhere, and other section forms don't reset it either.
    def apply_accessibility_params!
      nested = params.dig(:mic, :accessibility)
      return if nested.blank?
      access = (@mic.accessibility || {}).dup
      bool_cast = ActiveModel::Type::Boolean.new

      nested.to_unsafe_h.each do |key, raw|
        k = key.to_s
        if k == "wheelchair_level"
          # New 3-level field — string-valued. Blank / unknown is
          # stored as a removed key, not an empty string, so the
          # JSON column stays tidy.
          val = raw.to_s
          if %w[fully partial].include?(val)
            access[k] = val
          else
            access.delete(k)
          end
        else
          # Legacy boolean accessibility fields (e.g. low-vision flag
          # we might add later).
          access[k] = bool_cast.cast(raw) ? true : false
        end
      end
      @mic.accessibility = access
    end

    def humanize_role(role)
      case role
      when "owner"    then "Owner"
      when "co_owner" then "Co-owner"
      else role.humanize
      end
    end
  end
end
