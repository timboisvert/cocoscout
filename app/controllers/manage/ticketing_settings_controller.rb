# frozen_string_literal: true

module Manage
  # Ticketing settings, a routed-section page like Money and Contract settings:
  # the box office itself (its address, who pays fees, the pilot switch), tax
  # on tickets, who can work the door (and Tap to Pay on iPhone there).
  # No branding in v1 — every org gets the same pages.
  #
  # The "Your website" tab (sections/_embed, the code for selling from an
  # organization's own site) is off the list until embeds are ready to offer
  # (Tim, 2026-10-19); the embed pages themselves still work.
  class TicketingSettingsController < Manage::TicketingBaseController
    SECTIONS = %w[box_office page refunds tax notifications door sharing comps].freeze
    SECTION_LABELS = { "box_office" => "Box office", "page" => "Box office page", "refunds" => "Refunds", "tax" => "Tax", "notifications" => "Notifications",
                       "door" => "Door", "sharing" => "Who sees sales", "comps" => "Comps" }.freeze
    DEFAULT_SECTION = "box_office"

    before_action :set_section, only: %i[show]

    def show
      @tax = TicketTaxSetting.current(Current.organization) if @section == "tax"
      load_door_access if @section == "door"
      @notifications = TicketingNotifications.new(Current.organization) if @section == "notifications"
    end

    # One person's or address's Ticketing emails, from its modal on the
    # Notifications tab: a plan (and the emails, for Pick my own), an address
    # added or renamed, or an address removed (TicketingNotifications).
    def update_notifications
      notifications = TicketingNotifications.new(Current.organization)
      key = params[:recipient].to_s
      if params[:remove] == "1"
        notifications.remove_address!(key)
        return redirect_to section_path("notifications"), notice: "#{key.delete_prefix('email:')} won't get Ticketing email any more."
      end

      saved = notifications.save_plan!(key, plan: params[:plan].to_s, kinds: Array(params[:kinds]).compact_blank, email: params[:email])
      plan = TicketingNotifications::PLANS.find { |p| p.key == saved.plan }
      what = saved.plan == "custom" ? "their own pick" : plan.label.downcase_first
      notice = saved.kinds.empty? ? "Saved. #{saved.name} gets no Ticketing email." : "Saved. #{saved.name} gets #{what}: #{helpers.pluralize(saved.kinds.size, 'email')}."
      redirect_to section_path("notifications"), notice: notice
    rescue ArgumentError => e
      redirect_to section_path("notifications"), alert: e.message
    end

    # POST ticketing/settings/open: the organization opens its own box office
    # (Tim, 2026-10-06). The public pages and checkout go live. (Course and
    # contract money already pools for every Pro organization —
    # CocoScoutBalance.pooled?.) Closing it again is a superadmin's call, on
    # the same tab.
    # The Refunds tab: the policy buyers see, for every production that
    # doesn't set its own (RefundPolicy).
    def update_refunds
      raw = params.require(:ticketing_profile).permit(:refund_choice, :refund_days, :refund_fees, :refund_policy_note)
      attrs = { refund_fees: raw[:refund_fees] == "1", refund_policy_note: raw[:refund_policy_note].to_s.strip.presence }
      attrs.merge!(RefundPolicy.attributes_for(raw[:refund_choice], raw[:refund_days]) || {})

      if ticketing_profile.update(attrs)
        redirect_to section_path("refunds"), notice: "Refund policy saved."
      else
        @section = "refunds"
        flash.now[:alert] = ticketing_profile.errors.full_messages.to_sentence
        render :show, status: :unprocessable_content
      end
    end

    # Who sees sales: what a production team manager, a production team
    # viewer and the cast see of a production's sales (TicketSalesAccess).
    def update_sharing
      attrs = params.require(:ticketing_profile).permit(:team_manager_sales, :team_viewer_sales, :cast_sales)
      if ticketing_profile.update(attrs)
        redirect_to section_path("sharing"), notice: "Saved. #{ticketing_profile.sharing_words}"
      else
        @section = "sharing"
        flash.now[:alert] = ticketing_profile.errors.full_messages.to_sentence
        render :show, status: :unprocessable_content
      end
    end

    # The box office's comp rules (CompRules): on at all, how many a date can
    # give away, and the production team's share of them.
    def update_comps
      raw = params.require(:ticketing_profile).permit(*CompRules::FIELDS)
      if ticketing_profile.update(CompRules.attributes_from(raw))
        redirect_to section_path("comps"), notice: "Saved. #{ticketing_profile.comp_rules_words.upcase_first}."
      else
        @section = "comps"
        flash.now[:alert] = ticketing_profile.errors.full_messages.to_sentence
        render :show, status: :unprocessable_content
      end
    end

    # The box office page (Tim, 2026-10-18): its layout, a welcome line, the
    # address, and a wide image.
    def update_page
      attrs = params.require(:ticketing_profile).permit(:box_office_layout, :welcome_line, :show_address, :wide_image)
      attrs[:welcome_line] = attrs[:welcome_line].to_s.squish.presence if attrs.key?(:welcome_line)
      ticketing_profile.wide_image.purge_later if params[:remove_wide_image] == "1" && ticketing_profile.wide_image.attached?
      if ticketing_profile.update(attrs)
        redirect_to section_path("page"), notice: "Box office page saved."
      else
        @section = "page"
        flash.now[:alert] = ticketing_profile.errors.full_messages.to_sentence
        render :show, status: :unprocessable_content
      end
    end

    def open_box_office
      ticketing_profile.update!(enabled: true)
      notice = "Your box office is open. Buyers can find your shows at your box office link."
      # The end of a new organization's onboarding says how to turn on Tap to Pay on iPhone (Apple 3.4).
      if TapToPay.available_for?(Current.organization)
        notice += " To take cards at the door on an iPhone, open the CocoScout app and choose Tap to Pay on iPhone in the menu."
      elsif TapToPay.offered_to?(Current.organization)
        notice += " To take cards at the door on an iPhone, turn on Tap to Pay on iPhone in Ticketing settings, on the Door tab."
      end
      redirect_to manage_ticketing_path, notice: notice
    end

    def update
      attrs = params.require(:ticketing_profile)
                    .permit(:slug, :support_email, :default_fee_mode, :default_max_per_order,
                            :reminder_days_before, :enabled)
      # Closing a box office (or reopening it from here) is a superadmin's call;
      # managers open theirs with open_box_office.
      attrs.delete(:enabled) unless Current.user.superadmin?

      if ticketing_profile.update(attrs)
        redirect_to section_path("box_office"), notice: "Box office settings saved."
      else
        @section = "box_office"
        flash.now[:alert] = ticketing_profile.errors.full_messages.to_sentence
        render :show, status: :unprocessable_content
      end
    end

    def update_tax
      tax = params.fetch(:tax, {}).permit(:name, :percent, :mode, :set_aside)
      rule = TicketTaxSetting.save!(Current.organization, name: tax[:name], percent: tax[:percent], mode: tax[:mode])
      save_set_aside!(tax[:set_aside]) if tax.key?(:set_aside)
      redirect_to section_path("tax"), notice: rule ? "Tax on tickets saved." : "Tickets now carry no tax."
    rescue ArgumentError, ActiveRecord::RecordInvalid => e
      redirect_to section_path("tax"), alert: e.message
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
        "#{added == 1 ? users.first.person&.name || 'They' : "#{added} people"} can now #{level == 'box_office' ? 'check people in and sell tickets' : 'check people in'} at the door."
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

    # When the Door shows in the CocoScout app's menu: smart (show days, from
    # the morning or some hours before) or always (DoorTonight).
    def update_door_in_app
      attrs = params.require(:ticketing_profile).permit(:door_in_app, :door_hours_before)
      attrs[:door_hours_before] = attrs[:door_hours_before].presence
      if ticketing_profile.update(attrs)
        redirect_to section_path("door"), notice: "Saved. The app shows the Door #{ticketing_profile.door_in_app == 'always' ? 'all the time' : 'on show days'}."
      else
        redirect_to section_path("door"), alert: ticketing_profile.errors.full_messages.to_sentence
      end
    end

    # Tap to Pay on iPhone at this organization's door, from its modal on the
    # Door tab: on or off. Switching it on offers it here from then on.
    def update_tap_to_pay
      return redirect_to(section_path("door")) unless TapToPay.offered_to?(Current.organization, Current.user)

      on = params.dig(:ticketing_profile, :tap_to_pay) == "1"
      ticketing_profile.update!(tap_to_pay: on, tap_to_pay_offered: true)
      notice = if !on
        "Tap to Pay on iPhone is off."
      elsif ticketing_profile.enabled?
        "Tap to Pay on iPhone is on. To set up an iPhone, open the CocoScout app and choose Tap to Pay on iPhone in the menu."
      else
        "Tap to Pay on iPhone is on. It starts working once your box office is open."
      end
      redirect_to section_path("door"), notice: notice
    end

    def revoke_door_access
      grant = door_grants.find(params[:id])
      grant.revoke!(by: Current.user)
      redirect_to section_path("door"), notice: grant.pending? ? "Invitation to #{grant.invited_email} withdrawn." : "#{grant.display_name} can no longer work the door."
    end

    private

    # On: tax collected from today on is set aside (an organization already
    # on keeps its start date). Off: nothing is set aside.
    def save_set_aside!(value)
      org = Current.organization
      if value == "1"
        org.update_column(:sales_tax_set_aside_since, Date.current) unless org.sales_tax_set_aside_since
      else
        org.update_column(:sales_tax_set_aside_since, nil)
      end
    end

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
      # Who the People Picker marks "Has the door": managers always have it.
      @door_taken_person_ids = Person.where(user_id: (granted + managers).compact.uniq).pluck(:id)
      # The organization's managers, named at the top of the list: they can
      # always check people in and sell tickets (Tim, 2026-10-16).
      @door_managers = User.where(id: managers.uniq).includes(:default_person).to_a
                           .map { |user| user.person&.name.presence || user.email_address }.sort_by(&:downcase)
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
