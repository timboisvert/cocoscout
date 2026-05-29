# frozen_string_literal: true

module Manage
  module Staffing
    class StaffController < Manage::ManageController
      before_action :ensure_org_owner_or_manager
      before_action :set_staff_member, only: %i[update destroy]

      def index
        @staff_members = Current.organization.organization_staff_members
                                .active
                                .includes(:person, :house_roles)
                                .joins(:person)
                                .order("people.name")
        @house_roles = Current.organization.house_roles.active.ordered
        # Available people for the picker (org members not already on staff).
        # Embedded as JSON in the page so the picker can filter client-side.
        @available_people_payload = available_org_people.map { |p|
          headshot_variant = (p.respond_to?(:safe_headshot_variant) ? p.safe_headshot_variant(:thumb) : nil)
          {
            id: p.id,
            name: p.name,
            email: p.email,
            initials: p.initials,
            headshot_url: headshot_variant ? url_for(headshot_variant) : nil
          }
        }
        # Emails with an outstanding (unaccepted) invite to this org — used to
        # flag staff who haven't set up their CocoScout account yet.
        @pending_invite_emails = PersonInvitation.pending
                                                 .where(organization: Current.organization)
                                                 .pluck(:email)
                                                 .map { |e| e.to_s.downcase }
                                                 .to_set
      end

      # new/edit aren't used in the normal flow — the modal on the index page
      # handles both. Redirect direct navigation to the index.
      def new
        redirect_to manage_staffing_staff_path
      end

      def edit
        redirect_to manage_staffing_staff_path
      end

      def create
        # Two paths: add an existing org person (person_id), or invite a brand-new
        # person to CocoScout by email and add them as staff in one step.
        return invite_new_staff_member if params[:invite_email].present?

        @staff_member = Current.organization.organization_staff_members.new(person_id: params[:person_id])
        if @staff_member.save
          sync_role_ids(@staff_member, params[:house_role_ids])
          redirect_to manage_staffing_staff_path, notice: "Staff member added."
        else
          redirect_to manage_staffing_staff_path,
                      alert: "Couldn't add staff member: #{@staff_member.errors.full_messages.to_sentence}"
        end
      end

      def update
        sync_role_ids(@staff_member, params[:house_role_ids])
        redirect_to manage_staffing_staff_path, notice: "Staff member updated."
      end

      def destroy
        @staff_member.archive!
        redirect_to manage_staffing_staff_path, notice: "Staff member removed."
      end

      private

      # Invite a person who may have no CocoScout account yet, and add them to
      # this org's staff with the chosen roles immediately (so they're assignable
      # to shifts right away). The emailed invitation just grants account access.
      def invite_new_staff_member
        email = params[:invite_email].to_s.strip.downcase
        name  = params[:invite_name].to_s.strip

        unless email.match?(URI::MailTo::EMAIL_REGEXP)
          redirect_to manage_staffing_staff_path, alert: "Enter a valid email to invite someone." and return
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

          redirect_to manage_staffing_staff_path,
                      notice: "Invited #{person.name} and added them to staff."
        end
      rescue ActiveRecord::RecordInvalid => e
        redirect_to manage_staffing_staff_path, alert: "Couldn't invite: #{e.record.errors.full_messages.to_sentence.presence || e.message}"
      end

      def set_staff_member
        @staff_member = Current.organization.organization_staff_members.find(params[:id])
      end

      def available_org_people
        # People in the org who aren't already staff members.
        existing_ids = Current.organization.organization_staff_members.active.pluck(:person_id)
        Current.organization.people.where.not(id: existing_ids).order(:name)
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
