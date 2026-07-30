# frozen_string_literal: true

module Manage
  module Staffing
    # Gusto-style "add a staff member" wizard. Multi-step, matching the show /
    # contract wizard model: state lives in the cache (keyed per user) between
    # steps, each step renders inside the shared wizard_layout, and the final
    # step creates the Person + OrganizationStaffMember and sends the onboarding
    # invite. One focused question per step. Sensitive info (SSN, bank) is never
    # entered here — the worker provides that to Stripe during their own
    # onboarding.
    class StaffWizardController < Manage::ManageController
      before_action :ensure_org_owner_or_manager
      before_action :load_wizard_state
      before_action :require_started, only: %i[job manager start roles save_roles review save_review
                                               invite save_invite select_invite_person invite_new_person clear_invite_person]
      # Agreement + Send operate on the staff member persisted at the Invite step
      # (once we know which CocoScout account they're tied to).
      before_action :require_persisted_member, only: %i[agreement save_agreement send_step save_send]

      # Step 1: Personal details
      def details
        @staff_member = build_preview_member
      end

      def save_details
        first = params[:first_name].to_s.strip
        last  = params[:last_name].to_s.strip

        if first.blank? || last.blank?
          flash.now[:alert] = "First and last name are required."
          @staff_member = build_preview_member
          return render :details, status: :unprocessable_entity
        end

        @wizard_state.merge!(
          first_name: first,
          middle_initial: params[:middle_initial].to_s.strip.first,
          last_name: last,
          preferred_first_name: params[:preferred_first_name].to_s.strip
        )
        save_wizard_state
        redirect_to manage_job_staffing_staff_wizard_path
      end

      # Step 2: Job (title + department)
      def job
        @staff_member = build_preview_member
        @departments = Current.organization.departments.ordered
      end

      def save_job
        @wizard_state.merge!(title: params[:title].to_s.strip, department: params[:department].to_s.strip)
        save_wizard_state
        redirect_to manage_manager_staffing_staff_wizard_path
      end

      # Step 3: Manager
      def manager
        @staff_member = build_preview_member
        @managers = active_staff_for_manager_select
        @selected_manager = @managers.find { |m| m.id == @wizard_state[:manager_id].to_i }
      end

      def save_manager
        @wizard_state[:manager_id] = params[:manager_id].to_s.strip
        save_wizard_state
        redirect_to manage_start_staffing_staff_wizard_path
      end

      # Step 4: Start date
      def start
        @staff_member = build_preview_member
      end

      def save_start
        @wizard_state[:start_date] = params[:start_date].to_s.strip
        save_wizard_state
        redirect_to manage_roles_staffing_staff_wizard_path
      end

      # Step 5: Roles (staff are paid per role — no default/fallback rate)
      def roles
        @staff_member = build_preview_member
        @house_roles = Current.organization.house_roles.active.ordered
      end

      def save_roles
        @wizard_state[:house_role_ids] = Array(params[:house_role_ids]).map(&:to_i).reject(&:zero?)
        @wizard_state[:role_rates] = params[:role_rates]&.to_unsafe_h || {}
        save_wizard_state
        redirect_to manage_review_staffing_staff_wizard_path
      end

      # End of the "Set up" group: read-only confirmation of everything entered.
      def review
        @staff_member = build_preview_member
        @manager = @wizard_state[:manager_id].present? ? active_staff_for_manager_select.find { |m| m.id == @wizard_state[:manager_id].to_i } : nil
        @selected_roles = Current.organization.house_roles.where(id: Array(@wizard_state[:house_role_ids])).ordered
      end

      # Leaving Review just advances to the Invite step — nothing is persisted
      # until we know which CocoScout account this person is tied to.
      def save_review
        redirect_to manage_invite_staffing_staff_wizard_path
      end

      # Staged step 1: connect them to a CocoScout account. Search for an existing
      # person; if there's no match, invite a brand-new one. Once someone is
      # picked we show them with the option to swap for someone else.
      def invite
        @selected_person = selected_invite_person
        @invite_email = @wizard_state[:invite_email].presence
        # A pending email-invite is "new" unless that email already has a login.
        @account_was_new = @invite_email.present? && User.find_by(email_address: @invite_email).nil?

        @query = params[:q].to_s.strip
        @searched = params.key?(:q)
        @has_pick = @selected_person.present? || @invite_email.present?
        @results = @has_pick ? [] : search_people(@query)
        # Only offer "invite a new user" once a search has come back empty.
        @no_results = @searched && !@has_pick && @results.empty?

        # Pre-fill the create-new form from whatever they searched, falling back to
        # the name from the Details step.
        query_is_email = @query.include?("@")
        @prefill_email = query_is_email ? @query : nil
        name_query = query_is_email ? nil : @query
        @prefill_first = name_query.present? ? name_query.split.first : (@wizard_state[:preferred_first_name].presence || @wizard_state[:first_name])
        @prefill_last  = name_query.present? ? name_query.split.drop(1).join(" ").presence : @wizard_state[:last_name]
        @prefill_mi    = @wizard_state[:middle_initial]
      end

      # Pick an existing CocoScout person from the search results.
      def select_invite_person
        person = Person.find_by(id: params[:person_id])
        if person
          @wizard_state[:selected_person_id] = person.id
          @wizard_state.delete(:invite_email)
          save_wizard_state
        end
        redirect_to manage_invite_staffing_staff_wizard_path
      end

      # Queue a brand-new person to invite (shown only when the search finds no
      # one). Captures the name + email from the create form and keeps the Details
      # step in sync. We DON'T create the account here — only remember the email —
      # so the name always reflects the latest edit; the person is created at
      # Continue (save_invite).
      def invite_new_person
        email = params[:email].to_s.strip.downcase
        first = params[:first_name].to_s.strip
        last  = params[:last_name].to_s.strip

        unless email.match?(URI::MailTo::EMAIL_REGEXP) && first.present? && last.present?
          redirect_to manage_invite_staffing_staff_wizard_path(q: params[:q]),
                      alert: "A first name, last name, and valid email are needed to invite someone new."
          return
        end

        @wizard_state.merge!(
          first_name: first,
          last_name: last,
          middle_initial: params[:middle_initial].to_s.strip.first,
          invite_email: email
        )
        @wizard_state.delete(:selected_person_id)
        save_wizard_state
        redirect_to manage_invite_staffing_staff_wizard_path
      end

      # "Choose someone else" — clear the pick and search again.
      def clear_invite_person
        @wizard_state.delete(:selected_person_id)
        @wizard_state.delete(:invite_email)
        save_wizard_state
        redirect_to manage_invite_staffing_staff_wizard_path
      end

      # Continue from Invite: resolve the person (an existing pick, or create one
      # now from the pending email + current Details name), then persist the
      # membership + roles. No invite email yet — that's the Send step.
      def save_invite
        unless @wizard_state[:selected_person_id].present? || @wizard_state[:invite_email].present?
          redirect_to manage_invite_staffing_staff_wizard_path, alert: "Find or invite the person first."
          return
        end

        staff_member = nil
        ActiveRecord::Base.transaction do
          person = if @wizard_state[:selected_person_id].present?
            Person.find(@wizard_state[:selected_person_id])
          else
            upsert_person(email: @wizard_state[:invite_email],
                          name: "#{@wizard_state[:first_name]} #{@wizard_state[:last_name]}".strip)
          end
          ensure_account_for(person)

          # Reuse any existing (possibly archived) membership for this person.
          staff_member = Current.organization.organization_staff_members.find_or_initialize_by(person: person)
          staff_member.assign_attributes(employment_attributes_from_state)
          staff_member.archived_at = nil
          staff_member.save!
          staff_member.sync_role_qualifications!(role_ids: @wizard_state[:house_role_ids], rates: @wizard_state[:role_rates])
        end

        @wizard_state[:staff_member_id] = staff_member.id
        save_wizard_state
        redirect_to manage_agreement_staffing_staff_wizard_path
      rescue ActiveRecord::RecordInvalid => e
        redirect_to manage_invite_staffing_staff_wizard_path,
                    alert: "Couldn't add staff member: #{e.record.errors.full_messages.to_sentence.presence || e.message}"
      end

      # Staged step 2: which staff agreement they'll be asked to accept. Preview
      # renders with this member's real details.
      def agreement
        @agreement_templates = Current.organization.staff_agreement_templates.active.order(:name)
        @selected_template = @agreement_templates.find { |t| t.id == params[:template_id].to_i } ||
                             @staff_member.staff_agreement_template ||
                             @agreement_templates.first
      end

      def save_agreement
        template = Current.organization.staff_agreement_templates.find_by(id: params[:template_id])
        @staff_member.update(staff_agreement_template: template) if template
        redirect_to manage_send_staffing_staff_wizard_path
      end

      # Staged step 3: send the onboarding invite (account + agreement), with any
      # edits the reviewer made to the message.
      def send_step
        @email_preview = StaffOnboardingInviter.preview(staff_member: @staff_member)
        user = @staff_member.person&.user
        # A brand-new account gets the standard "set your password" invite first;
        # an existing account goes straight to the (editable) onboarding email.
        @needs_account_setup = user.nil? || user.last_seen_at.blank?
        render :send # the view is send.html.erb; the action is send_step because `send` is reserved
      end

      def save_send
        invited = send_invite(@staff_member, subject: params[:email_subject], body: params[:email_body])
        clear_wizard_state

        notice = if invited
          "#{@staff_member.display_name} added to staff — we emailed and messaged them to complete onboarding."
        else
          "#{@staff_member.display_name} added to staff. Invite them to complete onboarding when you're ready."
        end
        redirect_to manage_staffing_index_path, notice: notice
      end

      def cancel
        clear_wizard_state
        redirect_to manage_staffing_index_path, notice: "Cancelled adding a staff member."
      end

      private

      def require_started
        redirect_to manage_new_staffing_staff_wizard_path if @wizard_state[:first_name].blank?
      end

      # Loads the staff member persisted at the end of Review. Falls back to Review
      # if the wizard state was lost (e.g. cache expiry) so the staged steps never
      # run without a record.
      def require_persisted_member
        @staff_member = Current.organization.organization_staff_members.find_by(id: @wizard_state[:staff_member_id])
        redirect_to manage_review_staffing_staff_wizard_path if @staff_member.nil?
      end

      # A non-persisted OrganizationStaffMember carrying the in-progress state, so
      # the step views can reuse the same field helpers/prefills.
      def build_preview_member
        Current.organization.organization_staff_members.new(employment_attributes_from_state)
      end

      def employment_attributes_from_state
        {
          first_name: @wizard_state[:first_name].presence,
          middle_initial: @wizard_state[:middle_initial].to_s.first,
          last_name: @wizard_state[:last_name].presence,
          preferred_first_name: @wizard_state[:preferred_first_name].presence,
          title: @wizard_state[:title].presence,
          department: @wizard_state[:department].presence,
          start_date: @wizard_state[:start_date].presence,
          manager_id: valid_manager_id(@wizard_state[:manager_id]),
          onboarding_state: "added"
        }
      end

      # The CocoScout person picked (or invited) on the Invite step, if any.
      def selected_invite_person
        id = @wizard_state[:selected_person_id]
        id.present? ? Person.find_by(id: id) : nil
      end

      # Search people by name / email / public key to connect an existing account.
      def search_people(query)
        return [] if query.blank?

        like = "%#{query}%"
        Person.where("name ILIKE :q OR email ILIKE :q OR public_key ILIKE :q", q: like)
              .order(:name).limit(8).to_a
      end

      # Make sure the picked person is in this org and has a CocoScout login.
      def ensure_account_for(person)
        person.organizations << Current.organization unless person.organizations.include?(Current.organization)
        return if person.user.present? || person.email.blank?

        user = User.find_by(email_address: person.email) ||
               User.create!(email_address: person.email, password: User.generate_secure_password)
        person.update!(user: user)
      end

      def valid_manager_id(id)
        return nil if id.blank?

        Current.organization.organization_staff_members.active.where(id: id).pick(:id)
      end

      def active_staff_for_manager_select
        Current.organization.organization_staff_members.active.includes(:person)
               .order("people.name").references(:person).to_a
      end

      def upsert_person(email:, name:)
        person = Person.find_by(email: email) || Person.new(email: email)
        person.name = name if person.name.blank? || person.new_record?
        person.save!

        if person.user.nil?
          user = User.find_by(email_address: email) ||
                 User.create!(email_address: email, password: User.generate_secure_password)
          person.update!(user: user)
        end

        person.organizations << Current.organization unless person.organizations.include?(Current.organization)
        person
      end

      def send_invite(staff_member, subject: nil, body: nil)
        StaffOnboardingInviter.call(staff_member: staff_member, sender: Current.user, subject: subject, body: body)
        true
      rescue StaffOnboardingInviter::Error
        false
      end

      # ----- session-backed wizard state (mirrors the show wizard) -----

      def load_wizard_state
        @wizard_state = (Rails.cache.read(wizard_cache_key) || {}).with_indifferent_access
      end

      def save_wizard_state
        Rails.cache.write(wizard_cache_key, @wizard_state.to_h, expires_in: 24.hours)
      end

      def clear_wizard_state
        Rails.cache.delete(wizard_cache_key)
      end

      def wizard_cache_key
        "staff_wizard:#{Current.user.id}:#{Current.organization.id}"
      end
    end
  end
end
