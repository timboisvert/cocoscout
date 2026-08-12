# frozen_string_literal: true

module Manage
  class CourseOfferingsController < Manage::ManageController
    before_action :load_course_offering, only: %i[
      show edit update destroy open_registration close_registration
      mark_completed reopen archive unarchive
      search_instructor update_instructor invite_instructor
      cancel_registration refund_registration add_sessions
      enable_questionnaire disable_questionnaire send_questionnaire
      questionnaire update_questionnaire_settings
    ]

    def index
      all_offerings = Current.user.accessible_productions
        .courses
        .includes(course_offerings: [ :course_registrations, :course_offering_payout ])
        .flat_map(&:course_offerings)
        .sort_by(&:created_at)
        .reverse
      # Archived runs are hidden from the main list (collapsed section at the bottom).
      @archived_offerings = all_offerings.select(&:archived?)
      @course_offerings = all_offerings - @archived_offerings

      # Payouts overview: active courses, and which ones still owe money that
      # hasn't been sent to a payout run yet.
      @active_courses_count = @course_offerings.count { |o| o.status.in?(%w[open closed]) }
      @awaiting_payout = @course_offerings.select { |o| course_awaiting_payout?(o) }

      # An open course payout run with money still to send — surfaced so it's one
      # click from the hub.
      run = PayoutBatch.of_kind("course").open_runs
        .where(organization: Current.organization).order(:created_at).first
      @course_run_pending_cents = run&.items&.pending&.sum(:amount_cents).to_i
    end

    def show
      @registrations = @course_offering.course_registrations
        .where.not(status: :cancelled)
        .includes(:person)
        .order(registered_at: :desc)
      @sessions = @course_offering.sessions

      if @course_offering.questionnaire_id?
        @questionnaire_responses_by_person = @course_offering.questionnaire
          .questionnaire_responses
          .where(respondent_type: "Person")
          .index_by(&:respondent_id)
      end
    end

    def edit
      @sessions = @course_offering.sessions.includes(:location)
      @instructor_people = @course_offering.instructor_people.to_a
    end

    def update
      tab = params[:tab].to_i

      # Handle promo code for pricing tab
      if tab == 2
        handle_promo_code_for_update
      end

      if @course_offering.update(course_offering_params)
        # Re-sync Stripe prices if the offering is already open and pricing fields changed
        if @course_offering.open? && @course_offering.stripe_product_id.present? &&
           (@course_offering.saved_change_to_price_cents? ||
            @course_offering.saved_change_to_early_bird_price_cents? ||
            @course_offering.saved_change_to_early_bird_deadline? ||
            @course_offering.saved_change_to_currency?)
          begin
            CourseOfferingStripeService.new(@course_offering).ensure_stripe_resources!
          rescue CourseOfferingStripeService::StripeError => e
            redirect_to manage_edit_course_offering_path(@course_offering, tab: tab),
                        alert: "Pricing saved but failed to update Stripe: #{e.message}"
            return
          end
        end
        redirect_to manage_edit_course_offering_path(@course_offering, tab: tab), notice: "Course offering updated."
      else
        @sessions = @course_offering.sessions.includes(:location)
        @instructor_people = @course_offering.instructor_people.to_a
        render :edit, status: :unprocessable_entity
      end
    end

    def search_instructor
      query = params[:q].to_s.strip
      if query.length < 2
        render partial: "manage/course_offering_wizard/instructor_search_results",
               locals: { org_people: [], global_people: [], query: query, show_invite: false }
        return
      end

      # Search within org people first
      org_people = Current.organization.people.where(
        "LOWER(name) LIKE LOWER(:q) OR LOWER(email) LIKE LOWER(:q)",
        q: "%#{query}%"
      ).limit(10).to_a

      # Search globally (exclude org people)
      org_person_ids = Current.organization.people.pluck(:id)
      global_people = Person.where(
        "LOWER(name) LIKE LOWER(:q) OR LOWER(email) LIKE LOWER(:q)",
        q: "%#{query}%"
      ).where.not(id: org_person_ids).limit(10).to_a

      # Show invite if query looks like an email with no exact match
      show_invite = query.include?("@") &&
        org_people.none? { |p| p.email&.downcase == query.downcase } &&
        global_people.none? { |p| p.email&.downcase == query.downcase }

      render partial: "manage/course_offering_wizard/instructor_search_results",
             locals: { org_people: org_people, global_people: global_people, query: query, show_invite: show_invite }
    end

    def update_instructor
      person_ids = Array(params[:instructor_person_ids]).map(&:to_i).reject(&:zero?)
      instructor_on_team = params[:instructor_on_team] == "1"
      bios = params[:instructor_bios] || {}
      headshots = params[:instructor_headshots] || {}
      photo_modes = params[:instructor_photo_modes] || {}
      payout_types = params[:instructor_payout_types] || {}
      payout_values = params[:instructor_payout_values] || {}

      updates = {}
      if person_ids.any?
        people = Person.where(id: person_ids)
        updates[:instructor_person_id] = person_ids.first
        updates[:instructor_name] = people.pluck(:name).join(", ")
      else
        updates[:instructor_person_id] = nil
        updates[:instructor_name] = nil
      end
      updates[:instructor_on_team] = instructor_on_team
      updates[:instructor_preface] = params[:instructor_preface].presence
      updates[:show_individual_photos] = params[:show_individual_photos] == "1"
      updates[:show_individual_bios] = params[:show_individual_bios] == "1"
      if person_ids.size <= 1
        updates[:show_group_photo] = false
        updates[:show_group_bio] = false
        updates[:og_image_source] = "auto"
      else
        updates[:show_group_photo] = params[:show_group_photo] == "1"
        updates[:show_group_bio] = params[:show_group_bio] == "1"
        updates[:og_image_source] = params[:og_image_source].presence || "auto"
      end

      if @course_offering.update(updates)
        # Attach group photo if uploaded
        if params[:group_photo].present?
          @course_offering.group_photo.attach(params[:group_photo])
        end

        # Sync course_offering_instructors join records with per-instructor data
        existing_cois = @course_offering.course_offering_instructors.index_by(&:person_id)
        @course_offering.course_offering_instructors.where.not(person_id: person_ids).destroy_all

        person_ids.each_with_index do |pid, position|
          coi = existing_cois[pid] || @course_offering.course_offering_instructors.build(person_id: pid)
          coi.position = position
          coi.bio = bios[pid.to_s] if bios.key?(pid.to_s)

          mode = photo_modes[pid.to_s] || "profile"
          coi.hide_photo = (mode == "none")
          if mode == "upload" && headshots[pid.to_s].present?
            coi.headshot.attach(headshots[pid.to_s])
          elsif mode == "profile" && coi.headshot.attached?
            coi.headshot.purge
          end

          # Standalone (no-contract) payout split: one value interpreted per type.
          ptype = payout_types[pid.to_s].presence_in(CourseOfferingInstructor::PAYOUT_TYPES) || "none"
          value = payout_values[pid.to_s]
          coi.payout_type = ptype
          coi.payout_percentage = ptype == "percentage" ? value.presence : nil
          coi.payout_cents = ptype == "flat" ? (value.to_f * 100).round : nil

          coi.save!
        end

        # Assign all instructors to the Instructor role on all sessions
        person_ids.each do |pid|
          person = Person.find(pid)
          assign_instructor_to_sessions(@course_offering, person)
        end

        # Manage production team membership for all instructors
        manage_instructor_team_membership(@course_offering, person_ids)

        redirect_to manage_edit_course_offering_path(@course_offering, tab: 1), notice: "Instructor updated."
      else
        redirect_to manage_edit_course_offering_path(@course_offering, tab: 1), alert: "Failed to update instructor."
      end
    end

    def invite_instructor
      email = params[:email]&.strip&.downcase
      name = params[:name]&.strip

      if email.blank? || name.blank?
        render json: { success: false, error: "Name and email are required" }, status: :unprocessable_entity
        return
      end

      # Check if person with this email already exists
      existing_person = Person.find_by(email: email)

      if existing_person
        # Add to org if needed
        unless existing_person.organizations.include?(Current.organization)
          existing_person.organizations << Current.organization
        end

        render json: { success: true, person_id: existing_person.id, message: "#{existing_person.name} selected as instructor" }
      else
        # Create new person and user account
        person = Person.create!(name: name, email: email)
        person.organizations << Current.organization

        user = User.create!(
          email_address: email,
          password: User.generate_secure_password
        )
        person.update!(user: user)

        # Send invitation email
        invitation = PersonInvitation.create!(
          email: email,
          organization: Current.organization
        )
        Manage::PersonMailer.person_invitation(invitation).deliver_later

        render json: { success: true, person_id: person.id, message: "Invitation sent to #{name}" }
      end
    rescue ActiveRecord::RecordInvalid => e
      render json: { success: false, error: e.message }, status: :unprocessable_entity
    end

    def destroy
      if @course_offering.contract_id?
        redirect_to manage_course_offering_path(@course_offering),
          alert: "This course is linked to a contract and cannot be deleted here."
        return
      end

      # Any registration (even refunded — we keep that history) blocks a hard
      # delete. To get it off your lists, Archive it instead.
      if @course_offering.course_registrations.exists?
        redirect_to manage_course_offering_path(@course_offering),
          alert: "This course has registrations, so it can't be deleted (we keep that history). Archive it instead to hide it from your lists."
        return
      end

      production = @course_offering.production
      if @course_offering.destroy
        # Clean up the now-empty course production (no other runs, shows, or contracts).
        if production && production.course_offerings.reload.none? &&
           production.shows.reload.none? && production.contracts.none?
          production.destroy
        end
        redirect_to manage_course_offerings_path, notice: "Course deleted."
      else
        redirect_to manage_course_offering_path(@course_offering),
          alert: "Couldn't delete this course: #{@course_offering.errors.full_messages.to_sentence.presence || 'it still has linked records.'}"
      end
    end

    def add_sessions
      production = @course_offering.production
      session_rules_json = params[:session_rules_json]

      if session_rules_json.blank?
        redirect_to manage_edit_course_offering_path(@course_offering, tab: 2), alert: "No sessions to add."
        return
      end

      rules = JSON.parse(session_rules_json) rescue []
      created_count = 0

      rules.each do |rule|
        type = rule["type"]
        duration = (rule["duration_minutes"] || 60).to_i

        if type == "single" && rule["datetime"].present?
          dt = DateTime.parse(rule["datetime"]) rescue nil
          next unless dt
          production.shows.create!(
            date_and_time: dt,
            duration_minutes: duration,
            event_type: "class",
            course_offering: @course_offering,
            location: @course_offering.sessions.last&.location
          )
          created_count += 1
        elsif type == "recurring"
          expand_recurring_sessions(rule).each do |session_dt|
            production.shows.create!(
              date_and_time: session_dt,
              duration_minutes: duration,
              event_type: "class",
              course_offering: @course_offering,
              location: @course_offering.sessions.last&.location
            )
            created_count += 1
          end
        end
      end

      # Assign instructors to new sessions
      @course_offering.instructor_people.each do |person|
        assign_instructor_to_sessions(@course_offering, person)
      end

      redirect_to manage_edit_course_offering_path(@course_offering, tab: 2),
                  notice: "#{created_count} session#{'s' unless created_count == 1} added."
    end

    def open_registration
      # Create/update Stripe product and prices
      begin
        CourseOfferingStripeService.new(@course_offering).ensure_stripe_resources!
        @course_offering.update!(status: :open)
        redirect_to manage_course_offering_path(@course_offering), notice: "Registration is now open."
      rescue CourseOfferingStripeService::StripeError => e
        redirect_to manage_course_offering_path(@course_offering),
                    alert: "Failed to set up payment processing: #{e.message}"
      end
    end

    def close_registration
      @course_offering.update!(status: :closed)
      redirect_to manage_course_offering_path(@course_offering), notice: "Registration has been closed."
    end

    # Mark a run finished — it leaves the "Active courses" count and moves to the
    # Completed section. (Auto-applied by CourseOfferingCompletionJob once every
    # session has passed; this is the manual override.)
    def mark_completed
      @course_offering.update!(status: :completed)
      redirect_to manage_course_offering_path(@course_offering), notice: "Course marked completed."
    end

    def reopen
      @course_offering.update!(status: :closed)
      redirect_to manage_course_offering_path(@course_offering), notice: "Course reopened."
    end

    # Hide a course from the lists without deleting it (keeps registrations/history).
    def archive
      @course_offering.update!(status: :archived)
      redirect_to manage_course_offerings_path, notice: "Course archived — it's hidden from your course lists."
    end

    def unarchive
      @course_offering.update!(status: :closed)
      redirect_to manage_course_offering_path(@course_offering), notice: "Course restored."
    end

    def cancel_registration
      registration = @course_offering.course_registrations.find(params[:registration_id])

      if registration.confirmed? || registration.pending?
        registration.cancel!
        redirect_to manage_course_offering_path(@course_offering), notice: "#{registration.person.name} has been removed from the course."
      else
        redirect_to manage_course_offering_path(@course_offering), alert: "This registration cannot be cancelled."
      end
    end

    def refund_registration
      registration = @course_offering.course_registrations.find(params[:registration_id])

      unless registration.confirmed?
        redirect_to manage_course_offering_path(@course_offering), alert: "Only confirmed registrations can be refunded."
        return
      end

      # Process Stripe refund
      if registration.stripe_payment_intent_id.present?
        # The refund leaves the shared Stripe balance, so it must fit within
        # this org's own held money — reserve it on the cash ledger first.
        net = registration.org_net_cents
        if net.positive?
          begin
            OrgCashEntry.debit!(
              organization: registration.organization,
              amount_cents: net,
              source: registration,
              entry_type: "refund",
              description: "Refund of course registration ##{registration.id}"
            )
          rescue OrgCashEntry::InsufficientFunds
            redirect_to manage_course_offering_path(@course_offering),
              alert: "Your organization's held balance can't cover this refund right now."
            return
          end
        end

        begin
          refund = Stripe::Refund.create(
            payment_intent: registration.stripe_payment_intent_id,
            metadata: { organization_id: registration.organization&.id, course_registration_id: registration.id }
          )
          # The webhook will call registration.refund! when the charge.refunded event fires.
          # But we also mark it here for immediate UI feedback, capturing the refund
          # id so the course can trace back to the exact Stripe refund.
          registration.refund!(stripe_refund_id: refund.id)
          redirect_to manage_course_offering_path(@course_offering), notice: "#{registration.person.name} has been refunded and removed."
        rescue Stripe::StripeError => e
          # The money never left — release the reservation.
          OrgCashEntry.unpost!(source: registration, entry_type: "refund")
          redirect_to manage_course_offering_path(@course_offering), alert: "Refund failed: #{e.message}"
        end
      else
        # No payment intent — just mark as refunded
        registration.refund!
        redirect_to manage_course_offering_path(@course_offering), notice: "#{registration.person.name} has been marked as refunded."
      end
    end

    def enable_questionnaire
      if @course_offering.questionnaire.present?
        redirect_to manage_edit_course_offering_path(@course_offering, tab: 3), notice: "Questionnaire is already enabled."
        return
      end

      questionnaire = Questionnaire.create!(
        organization: Current.organization,
        title: "#{@course_offering.title} - Registration Questionnaire",
        accepting_responses: true
      )

      @course_offering.update!(questionnaire: questionnaire, delivery_mode: "immediate")

      redirect_to manage_form_contacts_questionnaire_path(questionnaire),
                  notice: "Questionnaire created. Add your questions below."
    end

    def disable_questionnaire
      @course_offering.update!(questionnaire: nil, delivery_mode: nil, delivery_delay_minutes: nil, delivery_scheduled_at: nil)
      redirect_to manage_edit_course_offering_path(@course_offering, tab: 3), notice: "Questionnaire disabled."
    end

    def send_questionnaire
      unless @course_offering.questionnaire.present?
        redirect_to manage_edit_course_offering_path(@course_offering, tab: 3), alert: "No questionnaire configured."
        return
      end

      count = 0
      @course_offering.course_registrations.where(status: :confirmed).find_each do |registration|
        next if @course_offering.questionnaire.questionnaire_invitations.exists?(invitee: registration.person, context: @course_offering)

        CourseQuestionnaireDeliveryJob.perform_later(registration.id)
        count += 1
      end

      redirect_to manage_course_offering_path(@course_offering),
                  notice: "Questionnaire queued for #{count} #{'registrant'.pluralize(count)}."
    end

    def questionnaire
      @questionnaire = @course_offering.questionnaire
      @available_questionnaires = Current.organization.questionnaires.active.order(:title)

      if @questionnaire
        @context_invited = @questionnaire.questionnaire_invitations.where(context: @course_offering).count
        @context_responded = @questionnaire.questionnaire_responses.where(context: @course_offering).count
        @context_responses = @questionnaire.questionnaire_responses
          .where(context: @course_offering)
          .includes(:respondent)
          .order(created_at: :desc)

        @email_draft = @course_offering.email_draft || @course_offering.build_email_draft(
          title: "Please complete a questionnaire",
          body: '<p>Hi {{person_name}},</p><p>Please fill out the following questionnaire:</p><p><a href="{{questionnaire_url}}">{{questionnaire_title}}</a></p>'
        )
      end
    end

    def update_questionnaire_settings
      if params[:questionnaire_id] == ""
        # Unlinking questionnaire — also remove the saved email draft
        @course_offering.email_draft&.destroy
        @course_offering.update!(questionnaire: nil, delivery_mode: nil, delivery_delay_minutes: nil, delivery_scheduled_at: nil)
        redirect_to manage_course_offering_questionnaire_path(@course_offering), notice: "Questionnaire unlinked."
        return
      end

      updates = {}
      if params[:questionnaire_id].present?
        questionnaire = Current.organization.questionnaires.find(params[:questionnaire_id])
        updates[:questionnaire_id] = questionnaire.id
      end
      updates[:delivery_mode] = params[:delivery_mode] if params[:delivery_mode].present?
      updates[:delivery_delay_minutes] = params[:delivery_delay_minutes] if params[:delivery_delay_minutes].present?
      updates[:delivery_scheduled_at] = params[:delivery_scheduled_at] if params[:delivery_scheduled_at].present?

      @course_offering.update!(updates)

      # Save email draft if provided
      if params[:email_draft].present?
        draft = @course_offering.email_draft || @course_offering.build_email_draft
        draft.update!(title: params[:email_draft][:title], body: params[:email_draft][:body])
      end

      redirect_to manage_course_offering_questionnaire_path(@course_offering), notice: "Questionnaire settings updated."
    end

    def validate_promo_code
      code = params[:code].to_s.strip
      credit = FeatureCredit.find_by_normalized_code(code)

      if credit.nil?
        render json: { valid: false, error: "Code not found" }
      elsif !credit.redeemable?
        render json: { valid: false, error: "This code is no longer valid" }
      elsif credit.feature_type != "courses"
        render json: { valid: false, error: "This code does not apply to courses" }
      else
        description = if credit.coverage_type == "platform_only"
          "Promo code applied — CocoScout platform fee waived! Stripe processing fees still apply."
        else
          "Promo code applied — all fees waived!"
        end
        render json: { valid: true, description: description, coverage_type: credit.coverage_type }
      end
    end

    private

    # A course is "awaiting payout" when it has taken money but the organization's
    # share hasn't been sent to a payout run yet.
    def course_awaiting_payout?(offering)
      has_confirmed =
        if offering.course_registrations.loaded?
          offering.course_registrations.any? { |r| r.status == "confirmed" }
        else
          offering.course_registrations.confirmed.exists?
        end
      return false unless has_confirmed

      payout = offering.course_offering_payout
      return true if payout.nil?
      # A payout marked paid is settled — whether through a Stripe run or recorded
      # as paid another way (e.g. an offline/historical payment). Without this, a
      # course paid outside a run stays "awaiting payout" forever.
      return false if payout.paid?

      !PayoutContribution.exists?(source: payout)
    end

    def load_course_offering
      @course_offering = CourseOffering.find(params[:id]) # rubocop:disable CocoScout/UnscopedFind -- org ownership checked immediately below (production.organization)
      # Verify it belongs to the current organization
      unless @course_offering.production.organization == Current.organization
        redirect_to manage_course_offerings_path, alert: "Course offering not found."
        return
      end
      @production = @course_offering.production
      # Verify user has access to this production
      unless Current.user.accessible_productions.include?(@production)
        redirect_to manage_course_offerings_path, alert: "You do not have access to this course offering."
      end
    end

    def course_offering_params
      permitted = params.require(:course_offering).permit(
        :title, :subtitle, :description,
        :early_bird_deadline,
        :currency, :capacity, :opens_at, :closes_at,
        :instruction_text, :success_text,
        :instructor_bio, :instructor_preface,
        :delivery_mode, :delivery_delay_minutes, :delivery_scheduled_at,
        :listed_in_directory
      )

      # Convert dollar amounts to cents
      if params[:course_offering][:price_dollars].present?
        permitted[:price_cents] = (params[:course_offering][:price_dollars].to_f * 100).round
      end

      if params[:course_offering][:early_bird_price_dollars].present?
        permitted[:early_bird_price_cents] = (params[:course_offering][:early_bird_price_dollars].to_f * 100).round
      elsif params[:course_offering].key?(:early_bird_price_dollars)
        # Explicitly cleared — set to nil
        permitted[:early_bird_price_cents] = nil
      end

      permitted
    end

    def handle_promo_code_for_update
      promo_code = params.dig(:course_offering, :promo_code).to_s.strip
      existing_redemption = @course_offering.feature_credit_redemption

      if promo_code.present? && existing_redemption.nil?
        # Applying a new promo code
        credit = FeatureCredit.find_by_normalized_code(promo_code)
        if credit&.redeemable? && credit.feature_type == "courses"
          redemption = credit.redeem!(
            organization: Current.organization,
            redeemable: @course_offering
          )
          @course_offering.update_column(:feature_credit_redemption_id, redemption.id)
        end
      elsif promo_code.blank? && existing_redemption.present?
        # Removing an existing promo code
        @course_offering.update_column(:feature_credit_redemption_id, nil)
      end
    end

    def assign_instructor_to_sessions(course_offering, person = nil)
      person ||= course_offering.instructor_person
      production = course_offering.production
      role = production.roles.find_by(name: "Instructor")
      return unless person && role

      # Add to org if not already
      unless Current.organization.people.exists?(id: person.id)
        Current.organization.people << person
      end

      # Add to talent pool
      pool = production.talent_pool
      unless pool.talent_pool_memberships.exists?(member: person)
        pool.talent_pool_memberships.create!(member: person)
      end

      # Assign to this run's sessions only
      course_offering.sessions.find_each do |show|
        ShowPersonRoleAssignment.find_or_create_by!(
          show: show,
          assignable: person,
          role: role
        )
      end
    end

    def manage_instructor_team_membership(course_offering, person_ids = nil)
      production = course_offering.production
      organization = production.organization
      people = if person_ids
        Person.where(id: person_ids)
      else
        course_offering.instructor_people.to_a
      end

      if course_offering.instructor_on_team?
        people.each do |person|
          next unless person.user.present?

          OrganizationRole.find_or_create_by!(
            user: person.user,
            organization: organization
          ) { |or_role| or_role.company_role = "member"; or_role.person = person }

          ProductionPermission.find_or_create_by!(
            user: person.user,
            production: production
          ) { |pp| pp.role = "manager" }

          setting = ProductionNotificationSetting.find_or_create_by!(
            user: person.user,
            production: production
          ) { |ns| ns.enabled = true }
          setting.update!(enabled: true) unless setting.enabled?
        end
      else
        people.each do |person|
          next unless person.user.present?

          ProductionPermission.where(
            user: person.user,
            production: production
          ).destroy_all
          ProductionNotificationSetting.where(
            user: person.user,
            production: production
          ).destroy_all

          remaining = ProductionPermission.joins(:production)
            .where(user: person.user, productions: { organization_id: organization.id })
            .exists?
          unless remaining
            OrganizationRole.where(user: person.user, organization: organization, company_role: "member").destroy_all
          end
        end
      end
    end

    def expand_recurring_sessions(rule)
      start_date = Date.parse(rule["start_date"])
      end_date = Date.parse(rule["end_date"])
      time_parts = (rule["time"] || "19:00").split(":")
      hour = time_parts[0].to_i
      minute = time_parts[1].to_i
      day_of_week = (rule["day_of_week"] || 1).to_i
      frequency = rule["frequency"] || "weekly"

      current = start_date
      days_ahead = (day_of_week - current.wday) % 7
      current += days_ahead

      step = frequency == "biweekly" ? 14 : 7
      sessions = []

      while current <= end_date
        sessions << Time.zone.local(current.year, current.month, current.day, hour, minute)
        current += step
      end

      sessions
    end
  end
end
