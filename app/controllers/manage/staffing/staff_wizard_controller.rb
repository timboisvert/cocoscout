# frozen_string_literal: true

module Manage
  module Staffing
    # Gusto-style "add a staff member" wizard: the employer enters employment
    # basics (name, personal email, title, hourly rate, manager, start date, and
    # the roles they can fill). Sensitive info (SSN, bank) is NOT collected here —
    # the worker provides that to Stripe during their own onboarding (Phase C).
    class StaffWizardController < Manage::ManageController
      before_action :ensure_org_owner_or_manager

      def new
        @staff_member = Current.organization.organization_staff_members.new(start_date: Date.current)
        load_form_collections
      end

      def create
        first = params[:first_name].to_s.strip
        last  = params[:last_name].to_s.strip
        email = params[:personal_email].to_s.strip.downcase

        @staff_member = Current.organization.organization_staff_members.new(employment_attributes)

        if first.blank? || last.blank? || !email.match?(URI::MailTo::EMAIL_REGEXP)
          @staff_member.errors.add(:base, "First name, last name, and a valid personal email are required.")
          load_form_collections
          return render :new, status: :unprocessable_entity
        end

        ActiveRecord::Base.transaction do
          person = upsert_person(email: email, name: "#{first} #{last}")

          @staff_member.person = person
          @staff_member.archived_at = nil
          # Reuse any existing (archived) membership for this person in the org.
          existing = Current.organization.organization_staff_members.find_by(person: person)
          @staff_member = existing.tap { |m| m.assign_attributes(employment_attributes) } if existing

          @staff_member.save!
          sync_role_ids(@staff_member, params[:house_role_ids])
        end

        redirect_to manage_staffing_index_path,
                    notice: "#{@staff_member.display_name} added to staff. Invite them to finish onboarding when you're ready."
      rescue ActiveRecord::RecordInvalid => e
        @staff_member.errors.add(:base, e.record.errors.full_messages.to_sentence.presence || e.message)
        load_form_collections
        render :new, status: :unprocessable_entity
      end

      private

      def employment_attributes
        {
          first_name: params[:first_name].to_s.strip.presence,
          middle_initial: params[:middle_initial].to_s.strip.first,
          last_name: params[:last_name].to_s.strip.presence,
          preferred_first_name: params[:preferred_first_name].to_s.strip.presence,
          personal_email: params[:personal_email].to_s.strip.downcase.presence,
          title: params[:title].to_s.strip.presence,
          hourly_rate_cents: parse_rate_cents(params[:hourly_rate]),
          start_date: params[:start_date].presence,
          manager_id: valid_manager_id(params[:manager_id]),
          onboarding_state: "added"
        }
      end

      def parse_rate_cents(value)
        return nil if value.blank?

        (value.to_s.delete("$,").to_d * 100).round
      end

      # Only accept a manager that is an active staff member in this org.
      def valid_manager_id(id)
        return nil if id.blank?

        Current.organization.organization_staff_members.active.where(id: id).pick(:id)
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

      def load_form_collections
        @house_roles = Current.organization.house_roles.active.ordered
        @managers = Current.organization.organization_staff_members.active.includes(:person).order("people.name").references(:person)
      end
    end
  end
end
