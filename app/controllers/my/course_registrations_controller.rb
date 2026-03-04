# frozen_string_literal: true

module My
  class CourseRegistrationsController < ApplicationController
    allow_unauthenticated_access only: %i[entry inactive]

    skip_before_action :show_my_sidebar

    before_action :ensure_user_is_signed_in, only: %i[show checkout success]
    before_action :load_course_offering
    before_action :ensure_course_is_open, except: %i[entry inactive success]

    def entry
      # If the user is already signed in, skip the sign-up page and go to details/checkout
      if authenticated?
        redirect_to my_course_show_path(code: @course_offering.short_code), status: :see_other
        return
      end

      @user = User.new
      @production = @course_offering.production

      # Set the return_to path so post-signup redirects to course details
      session[:return_to] = my_course_show_path(code: @course_offering.short_code)
    end

    def show
      @production = @course_offering.production
      @organization = @production.organization
      @sessions = @course_offering.upcoming_sessions
      @all_sessions = @course_offering.sessions.includes(:location)
      @person = Current.user.person

      # Check if already registered (confirmed only)
      @existing_registration = @course_offering.course_registrations
        .where(person: @person, status: :confirmed)
        .first
    end

    def checkout
      @person = Current.user.person

      # Check if already confirmed
      existing_confirmed = @course_offering.course_registrations
        .where(person: @person, status: :confirmed)
        .first

      if existing_confirmed
        redirect_to my_course_show_path(code: @course_offering.short_code),
                    alert: "You are already registered for this course."
        return
      end

      # Check capacity (includes Redis spot holds)
      if @course_offering.full?
        redirect_to my_course_show_path(code: @course_offering.short_code),
                    alert: "Sorry, this course is full."
        return
      end

      # Hold their spot for 5 minutes while they pay on Stripe
      hold_result = CourseSpotHoldService.acquire(@course_offering.id, @person.id)
      unless hold_result[:success]
        redirect_to my_course_show_path(code: @course_offering.short_code),
                    alert: "Unable to reserve your spot. Please try again."
        return
      end

      # Determine current price
      price_cents = @course_offering.current_price_cents
      stripe_price_id = if @course_offering.early_bird_active? && @course_offering.stripe_early_bird_price_id.present?
        @course_offering.stripe_early_bird_price_id
      else
        @course_offering.stripe_price_id
      end

      # Create Stripe Checkout Session — no database registration yet.
      # The registration will be created by the webhook after successful payment.
      checkout_session = Stripe::Checkout::Session.create(
        mode: "payment",
        line_items: [ {
          price: stripe_price_id,
          quantity: 1
        } ],
        customer_email: Current.user.email_address,
        success_url: my_course_success_url(code: @course_offering.short_code) + "?session_id={CHECKOUT_SESSION_ID}",
        cancel_url: my_course_show_url(code: @course_offering.short_code),
        metadata: {
          course_offering_id: @course_offering.id,
          person_id: @person.id,
          user_id: Current.user.id,
          amount_cents: price_cents,
          currency: @course_offering.currency
        }
      )

      redirect_to checkout_session.url, allow_other_host: true
    rescue Stripe::StripeError => e
      # Release the hold if Stripe fails
      CourseSpotHoldService.release(@course_offering.id, @person.id) if @person
      Rails.logger.error "Stripe checkout failed for course #{@course_offering.id}: #{e.message}"
      redirect_to my_course_show_path(code: @course_offering.short_code),
                  alert: "Unable to connect to our payment processor. Please try again."
    end

    def success
      @production = @course_offering.production
      @person = Current.user.person

      # Try to find an existing confirmed registration
      if params[:session_id].present?
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

    def inactive
      # If the course is actually open, redirect to register
      if @course_offering.open?
        redirect_to my_course_entry_path(code: @course_offering.short_code), status: :see_other
        return
      end

      @production = @course_offering.production
    end

    private

    def load_course_offering
      @course_offering = CourseOffering.find_by!(short_code: params[:code].upcase)
    rescue ActiveRecord::RecordNotFound
      redirect_to root_path, alert: "Course not found."
    end

    def ensure_course_is_open
      return if @course_offering.open?

      redirect_to my_course_inactive_path(code: @course_offering.short_code), status: :see_other
    end

    def ensure_user_is_signed_in
      return if authenticated?

      redirect_to my_course_entry_path(code: @course_offering.short_code), status: :see_other
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
        currency: metadata["currency"] || "usd",
        registered_at: Time.current,
        paid_at: Time.current,
        stripe_checkout_session_id: session.id,
        stripe_payment_intent_id: session.payment_intent
      )

      # Release Redis spot hold
      CourseSpotHoldService.release(@course_offering.id, @person.id)

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
