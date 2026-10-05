# frozen_string_literal: true

module My
  class CourseRegistrationsController < ApplicationController
    include CourseStorefront

    allow_unauthenticated_access only: %i[entry inactive show]

    before_action :ensure_user_is_signed_in, only: %i[show success calendar resend]
    before_action :ensure_course_is_open, except: %i[entry inactive success]

    def entry
      # If the user is already signed in, skip the sign-up page and go to details/checkout
      if authenticated?
        redirect_to my_course_show_path(code: @course_offering.short_code), status: :see_other
        return
      end

      @user = User.new
      @production = @course_offering.production
      @all_sessions = @course_offering.sessions.includes(:location, :location_space)

      # Set the return_to path so post-signup redirects to course details
      session[:return_to] = my_course_show_path(code: @course_offering.short_code)
      render :course
    end

    def show
      @production = @course_offering.production
      @organization = @production.organization
      @sessions = @course_offering.upcoming_sessions
      @all_sessions = @course_offering.sessions.includes(:location, :location_space)
      @person = Current.user.person

      # Check if already registered (confirmed only)
      @existing_registration = @course_offering.course_registrations
        .where(person: @person, status: :confirmed)
        .first
      render :course
    end

    def success
      @production = @course_offering.production
      @person = Current.user.person

      # From our own checkout: the registration by its token.
      if params[:token].present?
        @registration = @course_offering.course_registrations.confirmed.find_by(token: params[:token], person: @person)
      end

      # From Stripe's hosted page (anything still in flight from before).
      if @registration.nil? && params[:session_id].present?
        @registration = @course_offering.course_registrations
          .find_by(stripe_checkout_session_id: params[:session_id])

        # If webhook hasn't fired yet, create the registration from the Stripe session
        if @registration.nil?
          @registration = create_registration_from_stripe_session(params[:session_id])
        end
      end

      @registration ||= @course_offering.course_registrations
        .where(person: @person, status: :confirmed)
        .order(created_at: :desc)
        .first

      # If no registration found, redirect to the course page
      unless @registration
        redirect_to my_course_show_path(code: @course_offering.short_code)
        nil
      end
    end

    # "Add to calendar": every session as one .ics file.
    def calendar
      registration = own_registration
      sessions = @course_offering.sessions.includes(:location).to_a
      ics = Ticketing::Calendar.ics(sessions.map { |session|
        { uid: "course-registration-#{registration.id}-#{session.id}@cocoscout.com",
          starts: session.date_and_time, ends: session.date_and_time + (session.duration_minutes.to_i.positive? ? session.duration_minutes.minutes : 2.hours),
          summary: [ @course_offering.title, session.name_subtitle.presence ].compact.join(" · "),
          location: Ticketing::Calendar.place(session),
          description: "Your registration: #{my_course_success_url(code: @course_offering.short_code, token: registration.token)}" }
      })
      send_data ics, filename: "#{@course_offering.short_code.downcase}.ics", type: "text/calendar"
    end

    def resend
      registration = own_registration
      CourseRegistrationMailer.confirmation(registration).deliver_later
      redirect_to my_course_success_path(code: @course_offering.short_code, token: registration.token),
                  notice: "We've emailed your registration to #{registration.person&.email.presence || Current.user.email_address} again."
    end

    def inactive
      # If the course is actually open, redirect to register
      if @course_offering.open?
        redirect_to my_course_entry_path(code: @course_offering.short_code), status: :see_other
        return
      end

      @production = @course_offering.production
    end

    private

    # The signed-in person's own confirmed registration, by its token.
    def own_registration
      @course_offering.course_registrations.confirmed.find_by!(token: params[:token], person: Current.user.person)
    end

    # Fallback: if the Stripe webhook hasn't fired by the time the user
    # lands on the success page, retrieve the session and create the
    # registration inline. The webhook handler is idempotent and will
    # no-op if it arrives later.
    def create_registration_from_stripe_session(session_id)
      session = Stripe::Checkout::Session.retrieve(session_id)
      return nil unless session.payment_status == "paid"

      metadata = session.metadata
      return nil unless metadata["course_offering_id"].to_i == @course_offering.id

      person_id = metadata["person_id"].to_i
      return nil unless person_id == @person.id

      registration = @course_offering.course_registrations.create!(
        person: @person,
        user: Current.user,
        status: :confirmed,
        amount_cents: metadata["amount_cents"].to_i,
        tax_cents: metadata["tax_cents"].to_i,
        currency: metadata["currency"] || "usd",
        registered_at: Time.current,
        paid_at: Time.current,
        stripe_checkout_session_id: session.id,
        stripe_payment_intent_id: session.payment_intent,
        # The webhook path records the platform fee; this fallback used to skip
        # it, leaving the row (and the org's books) reading gross.
        cocoscout_fee_cents: CourseRegistration.platform_fee_cents_for(@course_offering, metadata["amount_cents"].to_i)
      )
      CourseTax.record!(registration)

      # Trigger confirmation (talent pool, emails, etc.)
      CourseRegistrationConfirmationJob.perform_later(registration.id)

      registration
    rescue ActiveRecord::RecordNotUnique
      # Webhook beat us — find the registration it created
      @course_offering.course_registrations
        .find_by(stripe_checkout_session_id: session_id)
    rescue Stripe::StripeError => e
      Rails.logger.error "Failed to retrieve Stripe session #{session_id}: #{e.message}"
      nil
    end
  end
end
