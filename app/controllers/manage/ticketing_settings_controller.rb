# frozen_string_literal: true

module Manage
  # Ticketing settings, a routed-section page like Money and Contract settings:
  # the box office itself (its address, who pays fees, the pilot switch), tax
  # on tickets, who can work the door, and the code for selling on the
  # theater's own website. No branding in v1 — every org gets the same pages.
  class TicketingSettingsController < Manage::TicketingBaseController
    SECTIONS = %w[box_office tax notifications door embed].freeze
    SECTION_LABELS = { "box_office" => "Box office", "tax" => "Tax", "notifications" => "Notifications",
                       "door" => "Door access", "embed" => "Your website" }.freeze
    DEFAULT_SECTION = "box_office"

    before_action :set_section, only: %i[show]

    def show
      @tax = TicketTaxSetting.current(Current.organization) if @section == "tax"
      load_door_access if @section == "door"
      @notifications = TicketingNotifications.new(Current.organization) if @section == "notifications"
    end

    # Who gets which Ticketing emails: the ticked managers and addresses per
    # kind, and the extra addresses themselves.
    def update_notifications
      rules = params[:rules].respond_to?(:each_pair) ? params[:rules].each_pair.to_h { |kind, keys| [ kind.to_s, Array(keys) ] } : {}
      emails = params[:emails].to_s.split(/[\s,;]+/)
      TicketingNotifications.new(Current.organization).save!(rules: rules, emails: emails)
      redirect_to section_path("notifications"), notice: "Notifications saved."
    rescue ArgumentError => e
      redirect_to section_path("notifications"), alert: e.message
    end

    def update
      attrs = params.require(:ticketing_profile)
                    .permit(:slug, :support_email, :default_fee_mode, :default_max_per_order, :refunds_after_show,
                            :reminder_days_before, :enabled)
      # The pilot switch is a superadmin's call, even once managers can get here.
      attrs.delete(:enabled) unless Current.user.superadmin?

      if ticketing_profile.update(attrs)
        redirect_to section_path("box_office"), notice: "Box office settings saved."
      else
        @section = "box_office"
        flash.now[:alert] = ticketing_profile.errors.full_messages.to_sentence
        render :show, status: :unprocessable_entity
      end
    end

    def update_tax
      tax = params.fetch(:tax, {}).permit(:name, :percent, :mode)
      rule = TicketTaxSetting.save!(Current.organization, name: tax[:name], percent: tax[:percent], mode: tax[:mode])
      redirect_to section_path("tax"), notice: rule ? "Tax on tickets saved." : "Tickets now carry no tax."
    rescue ArgumentError, ActiveRecord::RecordInvalid => e
      redirect_to section_path("tax"), alert: e.message
    end

    # Door access: anyone on CocoScout, found by name or email. Managers already
    # have the door, so they're marked rather than offered.
    def door_search
      q = params[:q].to_s.strip
      people = if q.length < 2
        []
      else
        like = "%#{Person.sanitize_sql_like(q)}%"
        Person.where.not(user_id: nil).where(archived_at: nil)
              .where("people.name ILIKE :q OR people.email ILIKE :q", q: like)
              .includes(:user).order(:name).limit(30).to_a.uniq(&:user_id).first(15)
      end
      render partial: "manage/ticketing_settings/door_search_results",
             locals: { people: people, query: q, granted_user_ids: door_grants.pluck(:user_id).compact, manager_user_ids: manager_user_ids }
    end

    # Gives door access to the staff members ticked, or to one person found by
    # search, at the chosen level. Someone who already has access moves to the
    # new level; managers are skipped (they always have the door).
    def grant_door_access
      level = params[:access_level].presence_in(TicketingAccessGrant::LEVELS)
      return redirect_to(section_path("door"), alert: "Choose what they can do at the door.") unless level

      users = door_candidates
      return redirect_to(section_path("door"), alert: "Choose someone to give door access to.") if users.empty?

      managers = manager_user_ids
      added = users.reject { |user| managers.include?(user.id) }.count do |user|
        grant = door_grants.find_or_initialize_by(user: user)
        grant.granted_by ||= Current.user
        grant.access_level = level
        grant.save
      end
      notice = if added.zero?
        "They're managers here, so they can already work the door."
      else
        "#{added == 1 ? users.first.person&.name || 'They' : "#{added} people"} can now #{level == 'box_office' ? 'work the box office' : 'check people in'} at the door."
      end
      redirect_to section_path("door"), notice: notice
    end

    # Door access for someone not found on CocoScout: they get an emailed
    # invitation, and the grant waits until they accept. Someone who turns out
    # to have an account under that email just gets access.
    def invite_door_access
      level = params[:access_level].presence_in(TicketingAccessGrant::LEVELS) || "check_in"
      email = params[:email].to_s.strip.downcase
      unless email.match?(URI::MailTo::EMAIL_REGEXP)
        redirect_to section_path("door"), alert: "Enter an email address to invite." and return
      end

      if (user = User.find_by(email_address: email))
        grant = door_grants.find_or_initialize_by(user: user)
        grant.granted_by ||= Current.user
        grant.update!(access_level: level)
        redirect_to section_path("door"), notice: "#{user.person&.name || email} can now #{grant.access_description} at the door." and return
      end

      grant = TicketingAccessGrant.invite!(organization: Current.organization, email: email, name: params[:name], level: level, by: Current.user)
      send_door_invitation(grant)
      redirect_to section_path("door"), notice: "Invitation sent to #{email}."
    rescue ActiveRecord::RecordInvalid => e
      redirect_to section_path("door"), alert: e.record.errors.full_messages.to_sentence
    end

    def resend_door_invite
      grant = Current.organization.ticketing_access_grants.pending_invites.find(params[:id])
      send_door_invitation(grant)
      redirect_to section_path("door"), notice: "Invitation sent again to #{grant.invited_email}."
    end

    def update_door_access
      grant = door_grants.find(params[:id])
      level = params[:access_level].presence_in(TicketingAccessGrant::LEVELS)
      grant.update!(access_level: level) if level
      redirect_to section_path("door"), notice: "Door access updated."
    end

    def revoke_door_access
      grant = door_grants.find(params[:id])
      grant.revoke!(by: Current.user)
      redirect_to section_path("door"), notice: grant.pending? ? "Invitation to #{grant.invited_email} withdrawn." : "#{grant.display_name} can no longer work the door."
    end

    private

    def door_grants
      Current.organization.ticketing_access_grants.active
    end

    def send_door_invitation(grant)
      AppMailer.with(template_key: "ticketing_door_invitation", to: grant.invited_email, variables: {
        first_name: grant.invited_name.to_s.split.first.presence || "there",
        inviter_name: Current.user.person&.name || Current.user.email_address,
        organization_name: Current.organization.name,
        access_description: grant.access_description,
        accept_url: door_invitation_url(token: grant.invitation_token)
      }).send_template.deliver_later
    end

    def manager_user_ids
      Current.organization.organization_roles.where(company_role: "manager").pluck(:user_id) + [ Current.organization.owner_id ]
    end

    # Staff ticked in the picker (this org's active staff only), or one person
    # chosen from the search — anyone with a CocoScout account.
    def door_candidates
      users = []
      ids = Array(params[:staff_member_ids]).compact_blank
      if ids.any?
        users += Current.organization.organization_staff_members.active.where(id: ids)
                        .includes(person: :user).filter_map { |member| member.person&.user }
      end
      if params[:person_id].present?
        person = Person.where.not(user_id: nil).where(id: params[:person_id]).first
        users << person.user if person
      end
      users.uniq
    end

    def load_door_access
      @door_grants = door_grants.includes(user: :default_person).to_a.sort_by { |grant| grant.display_name.to_s.downcase }
      granted = @door_grants.map(&:user_id)
      managers = manager_user_ids
      @door_staff = Current.organization.organization_staff_members.active.includes(person: :user).to_a
                           .reject { |member| member.person&.user_id.in?(granted) || member.person&.user_id.in?(managers) }
                           .sort_by { |member| member.display_name.to_s.downcase }
    end

    def sections
      SECTIONS.map { |key| { key: key, label: SECTION_LABELS.fetch(key), path: section_path(key) } }
    end
    helper_method :sections

    def section_path(key)
      manage_ticketing_settings_section_path(section: key)
    end

    def set_section
      @section = params[:section].presence || DEFAULT_SECTION
      redirect_to section_path(DEFAULT_SECTION) unless @section.in?(SECTIONS)
    end
  end
end
