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
      before_action :require_started, only: %i[job manager start pay roles save_roles review create]

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
        redirect_to manage_pay_staffing_staff_wizard_path
      end

      # Step 5: Pay
      def pay
        @staff_member = build_preview_member
      end

      def save_pay
        @wizard_state[:hourly_rate] = params[:hourly_rate].to_s.strip
        save_wizard_state
        redirect_to manage_roles_staffing_staff_wizard_path
      end

      # Step 6: Roles
      def roles
        @staff_member = build_preview_member
        @house_roles = Current.organization.house_roles.active.ordered
      end

      def save_roles
        @wizard_state[:house_role_ids] = Array(params[:house_role_ids]).map(&:to_i).reject(&:zero?)
        save_wizard_state
        redirect_to manage_review_staffing_staff_wizard_path
      end

      # Step 7: Review — confirm everything and edit the invite email before it
      # goes out.
      def review
        @staff_member = build_preview_member
        @manager = @wizard_state[:manager_id].present? ? active_staff_for_manager_select.find { |m| m.id == @wizard_state[:manager_id].to_i } : nil
        @selected_roles = Current.organization.house_roles.where(id: Array(@wizard_state[:house_role_ids])).ordered
        @email_preview = StaffOnboardingInviter.preview(staff_member: @staff_member)
      end

      # Final step: create the person + membership, then invite (with any edits
      # the reviewer made to the email).
      def create
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

        invited = send_invite(staff_member, subject: params[:email_subject], body: params[:email_body])
        clear_wizard_state

        notice = if invited
          "#{staff_member.display_name} added to staff — we emailed and messaged them to complete onboarding."
        else
          "#{staff_member.display_name} added to staff. Invite them to complete onboarding when you're ready."
        end
        redirect_to manage_staffing_index_path, notice: notice
      rescue ActiveRecord::RecordInvalid => e
        redirect_to manage_review_staffing_staff_wizard_path,
                    alert: "Couldn't add staff member: #{e.record.errors.full_messages.to_sentence.presence || e.message}"
      end

      def cancel
        clear_wizard_state
        redirect_to manage_staffing_index_path, notice: "Cancelled adding a staff member."
      end

      private

      def require_started
        redirect_to manage_new_staffing_staff_wizard_path if @wizard_state[:first_name].blank?
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
          personal_email: @wizard_state[:personal_email].presence,
          title: @wizard_state[:title].presence,
          department: @wizard_state[:department].presence,
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

      def sync_role_ids(staff_member, role_ids)
        ids = Array(role_ids).map(&:to_i).reject(&:zero?)
        valid = Current.organization.house_roles.where(id: ids).pluck(:id)
        staff_member.house_role_ids = valid
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
