# frozen_string_literal: true

module Manage
  module Staffing
    # Gusto-style "add a staff member" wizard. Multi-step, matching the show /
    # contract wizard model: state lives in the cache (keyed per user) between
    # steps, each step renders inside the shared wizard_layout, and the final
    # step creates the Person + OrganizationStaffMember and sends the onboarding
    # invite. Sensitive info (SSN, bank) is never entered here — the worker
    # provides that to Stripe during their own onboarding.
    class StaffWizardController < Manage::ManageController
      before_action :ensure_org_owner_or_manager
      before_action :load_wizard_state

      # Step 1: Personal details
      def details
        @staff_member = build_preview_member
      end

      def save_details
        first = params[:first_name].to_s.strip
        last  = params[:last_name].to_s.strip
        email = params[:personal_email].to_s.strip.downcase

        if first.blank? || last.blank? || !email.match?(URI::MailTo::EMAIL_REGEXP)
          flash.now[:alert] = "First name, last name, and a valid personal email are required."
          @staff_member = build_preview_member
          return render :details, status: :unprocessable_entity
        end

        @wizard_state.merge!(
          first_name: first,
          middle_initial: params[:middle_initial].to_s.strip.first,
          last_name: last,
          preferred_first_name: params[:preferred_first_name].to_s.strip,
          personal_email: email
        )
        save_wizard_state
        redirect_to manage_staffing_staff_wizard_employment_path
      end

      # Step 2: Employment
      def employment
        return redirect_to manage_new_staffing_staff_wizard_path if @wizard_state[:first_name].blank?

        @staff_member = build_preview_member
        @managers = active_staff_for_manager_select
      end

      def save_employment
        @wizard_state.merge!(
          title: params[:title].to_s.strip,
          hourly_rate: params[:hourly_rate].to_s.strip,
          start_date: params[:start_date].to_s.strip,
          manager_id: params[:manager_id].to_s.strip
        )
        save_wizard_state
        redirect_to manage_staffing_staff_wizard_roles_path
      end

      # Step 3: Roles
      def roles
        return redirect_to manage_new_staffing_staff_wizard_path if @wizard_state[:first_name].blank?

        @staff_member = build_preview_member
        @house_roles = Current.organization.house_roles.active.ordered
      end

      # Final step: create the person + membership, then invite.
      def create
        return redirect_to manage_new_staffing_staff_wizard_path if @wizard_state[:first_name].blank?

        @wizard_state[:house_role_ids] = Array(params[:house_role_ids]).map(&:to_i).reject(&:zero?)
        save_wizard_state

        staff_member = nil
        ActiveRecord::Base.transaction do
          person = upsert_person(email: @wizard_state[:personal_email],
                                  name: "#{@wizard_state[:first_name]} #{@wizard_state[:last_name]}")

          # Reuse any existing (possibly archived) membership for this person.
          staff_member = Current.organization.organization_staff_members.find_or_initialize_by(person: person)
          staff_member.assign_attributes(employment_attributes_from_state)
          staff_member.archived_at = nil
          staff_member.save!
          sync_role_ids(staff_member, @wizard_state[:house_role_ids])
        end

        invited = send_invite(staff_member)
        clear_wizard_state

        notice = if invited
          "#{staff_member.display_name} added to staff — we emailed and messaged them to set up how they get paid."
        else
          "#{staff_member.display_name} added to staff. Invite them to finish onboarding when you're ready."
        end
        redirect_to manage_staffing_index_path, notice: notice
      rescue ActiveRecord::RecordInvalid => e
        redirect_to manage_staffing_staff_wizard_roles_path,
                    alert: "Couldn't add staff member: #{e.record.errors.full_messages.to_sentence.presence || e.message}"
      end

      def cancel
        clear_wizard_state
        redirect_to manage_staffing_index_path, notice: "Cancelled adding a staff member."
      end

      private

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
          personal_email: @wizard_state[:personal_email].presence,
          title: @wizard_state[:title].presence,
          hourly_rate_cents: parse_rate_cents(@wizard_state[:hourly_rate]),
          start_date: @wizard_state[:start_date].presence,
          manager_id: valid_manager_id(@wizard_state[:manager_id]),
          onboarding_state: "added"
        }
      end

      def parse_rate_cents(value)
        return nil if value.blank?

        (value.to_s.delete("$,").to_d * 100).round
      end

      def valid_manager_id(id)
        return nil if id.blank?

        Current.organization.organization_staff_members.active.where(id: id).pick(:id)
      end

      def active_staff_for_manager_select
        Current.organization.organization_staff_members.active.includes(:person)
               .order("people.name").references(:person)
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

      def sync_role_ids(staff_member, role_ids)
        ids = Array(role_ids).map(&:to_i).reject(&:zero?)
        valid = Current.organization.house_roles.where(id: ids).pluck(:id)
        staff_member.house_role_ids = valid
      end

      def send_invite(staff_member)
        StaffOnboardingInviter.call(staff_member: staff_member, sender: Current.user)
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
