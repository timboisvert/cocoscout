# frozen_string_literal: true

module Manage
  module Staffing
    class StaffController < Manage::ManageController
      before_action :ensure_org_owner_or_manager
      before_action :set_staff_member, only: %i[edit update destroy invite]

      # The staffing hub (Manage::StaffingController#index) is now the one and
      # only staff roster. Keep this legacy path working by redirecting to it.
      def index
        redirect_to manage_staffing_index_path
      end

      def new
        redirect_to manage_staffing_index_path
      end

      # Full-page staff editor (roomy — replaces the old cramped modal).
      def edit
        @house_roles = Current.organization.house_roles.active.ordered
        @managers = Current.organization.organization_staff_members.active
                           .includes(:person).order("people.name").references(:person).to_a
      end

      def create
        # Two paths: add an existing org person (person_id), or invite a brand-new
        # person to CocoScout by email and add them as staff in one step.
        return invite_new_staff_member if params[:invite_email].present?

        @staff_member = Current.organization.organization_staff_members.new(person_id: params[:person_id])
        if @staff_member.save
          sync_role_ids(@staff_member, params[:house_role_ids])
          redirect_to manage_staffing_index_path, notice: "Staff member added."
        else
          redirect_to manage_staffing_index_path,
                      alert: "Couldn't add staff member: #{@staff_member.errors.full_messages.to_sentence}"
        end
      end

      def update
        @staff_member.assign_attributes(editable_employment_attributes)
        @staff_member.save!
        sync_role_ids(@staff_member, params[:house_role_ids])
        redirect_to manage_staffing_index_path, notice: "#{@staff_member.display_name} updated."
      rescue ActiveRecord::RecordInvalid => e
        redirect_to manage_staffing_index_path,
                    alert: "Couldn't update: #{e.record.errors.full_messages.to_sentence.presence || e.message}"
      end

      # Invite an already-added staffer to finish onboarding: ensure they have a
      # CocoScout account, then send BOTH an onboarding email (focused on setting
      # up how they get paid) and a parallel in-app message. Marks the membership
      # as "invited" so the staff list reflects where they are.
      def invite
        StaffOnboardingInviter.call(staff_member: @staff_member, sender: Current.user)
        redirect_to manage_staffing_index_path,
                    notice: "Invited #{@staff_member.display_name} to finish onboarding — we emailed and messaged them to set up how they get paid."
      rescue StaffOnboardingInviter::Error => e
        redirect_to manage_staffing_index_path, alert: e.message
      rescue ActiveRecord::RecordInvalid => e
        redirect_to manage_staffing_index_path,
                    alert: "Couldn't invite #{@staff_member.display_name}: #{e.record.errors.full_messages.to_sentence.presence || e.message}"
      end

      def destroy
        @staff_member.archive!
        redirect_to manage_staffing_index_path, notice: "Staff member removed."
      end

      private

      # Invite a person who may have no CocoScout account yet, and add them to
      # this org's staff with the chosen roles immediately (so they're assignable
      # to shifts right away). The emailed invitation just grants account access.
      def invite_new_staff_member
        email = params[:invite_email].to_s.strip.downcase
        name  = params[:invite_name].to_s.strip

        unless email.match?(URI::MailTo::EMAIL_REGEXP)
          redirect_to manage_staffing_index_path, alert: "Enter a valid email to invite someone." and return
        end

        ActiveRecord::Base.transaction do
          person = Person.find_by(email: email) || Person.new(email: email)
          person.name = name if name.present? && person.name.blank?
          person.name = email.split("@").first if person.name.blank?
          person.save!

          if person.user.nil?
            user = User.find_by(email_address: email) ||
                   User.create!(email_address: email, password: User.generate_secure_password)
            person.update!(user: user)
          end

          person.organizations << Current.organization unless person.organizations.include?(Current.organization)

          # Add (or un-archive) the staff membership, then sync roles. Uniqueness
          # is scoped to org and counts archived rows, so reuse any existing one.
          staff_member = Current.organization.organization_staff_members.find_or_initialize_by(person: person)
          staff_member.archived_at = nil
          staff_member.save!
          sync_role_ids(staff_member, params[:house_role_ids])

          invitation = PersonInvitation.create!(email: email, organization: Current.organization)
          Manage::PersonMailer.person_invitation(invitation).deliver_later

          redirect_to manage_staffing_index_path,
                      notice: "Invited #{person.name} and added them to staff."
        end
      rescue ActiveRecord::RecordInvalid => e
        redirect_to manage_staffing_index_path, alert: "Couldn't invite: #{e.record.errors.full_messages.to_sentence.presence || e.message}"
      end

      def set_staff_member
        @staff_member = Current.organization.organization_staff_members.find(params[:id])
      end

      def available_org_people
        # People in the org who aren't already staff members.
        existing_ids = Current.organization.organization_staff_members.active.pluck(:person_id)
        Current.organization.people.where.not(id: existing_ids).order(:name)
      end

      # Only assign employment fields that were actually submitted, so a partial
      # form (e.g. the Roles tab alone) never blanks out other details.
      def editable_employment_attributes
        attrs = {}
        attrs[:preferred_first_name] = params[:preferred_first_name].to_s.strip.presence if params.key?(:preferred_first_name)
        attrs[:first_name] = params[:first_name].to_s.strip.presence if params.key?(:first_name)
        attrs[:middle_initial] = params[:middle_initial].to_s.strip.first if params.key?(:middle_initial)
        attrs[:last_name] = params[:last_name].to_s.strip.presence if params.key?(:last_name)
        attrs[:title] = params[:title].to_s.strip.presence if params.key?(:title)
        attrs[:department] = params[:department].to_s.strip.presence if params.key?(:department)
        attrs[:personal_email] = params[:personal_email].to_s.strip.downcase.presence if params.key?(:personal_email)
        attrs[:start_date] = params[:start_date].presence if params.key?(:start_date)
        attrs[:hourly_rate_cents] = parse_rate_cents(params[:hourly_rate]) if params.key?(:hourly_rate)
        attrs[:manager_id] = valid_manager_id(params[:manager_id]) if params.key?(:manager_id)
        attrs
      end

      def parse_rate_cents(value)
        return nil if value.blank?

        (value.to_s.delete("$,").to_d * 100).round
      end

      def valid_manager_id(id)
        return nil if id.blank? || id.to_i == @staff_member&.id

        Current.organization.organization_staff_members.active.where(id: id).pick(:id)
      end

      def sync_role_ids(staff_member, role_ids)
        ids = Array(role_ids).map(&:to_i).reject(&:zero?)
        # Only allow this org's roles.
        ids &= Current.organization.house_roles.pluck(:id)

        current = staff_member.house_role_ids
        to_add = ids - current
        to_remove = current - ids

        StaffRoleQualification.where(
          organization_staff_member_id: staff_member.id,
          house_role_id: to_remove
        ).delete_all if to_remove.any?

        to_add.each do |rid|
          staff_member.staff_role_qualifications.create!(house_role_id: rid)
        end
      end
    end
  end
end
