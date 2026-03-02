# frozen_string_literal: true

module My
  class CourseRegistrationsController < ApplicationController
    allow_unauthenticated_access only: %i[entry inactive]

    skip_before_action :show_my_sidebar

    before_action :ensure_user_is_signed_in, only: %i[show checkout success]
    before_action :load_course_offering
    before_action :ensure_course_is_open, except: %i[entry inactive success]

    def entry
      # If the user is already signed in, redirect them to the course details
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
      @person = Current.user.person

      # Check if already registered
      @existing_registration = @course_offering.course_registrations
        .where(person: @person)
        .where.not(status: %w[cancelled refunded])
        .first
    end

    def checkout
      @person = Current.user.person
      @production = @course_offering.production

      # Check if already registered
      existing = @course_offering.course_registrations
        .where(person: @person)
        .where.not(status: %w[cancelled refunded])
        .first

      if existing
        redirect_to my_course_show_path(code: @course_offering.short_code),
                    alert: "You are already registered for this course."
        return
      end

      # Check capacity
      if @course_offering.full?
        redirect_to my_course_show_path(code: @course_offering.short_code),
                    alert: "Sorry, this course is full."
        return
      end

      # Determine current price
      price_cents = @course_offering.current_price_cents
      stripe_price_id = if @course_offering.early_bird_active? && @course_offering.stripe_early_bird_price_id.present?
        @course_offering.stripe_early_bird_price_id
      else
        @course_offering.stripe_price_id
      end

      # Create the course registration (pending until payment confirmed)
      registration = @course_offering.course_registrations.create!(
        person: @person,
        user: Current.user,
        status: :pending,
        amount_cents: price_cents,
        currency: @course_offering.currency,
        registered_at: Time.current
      )

      # Create Stripe Checkout Session
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
          course_registration_id: registration.id,
          course_offering_id: @course_offering.id,
          person_id: @person.id
        }
      )

      # Store the checkout session ID on the registration
      registration.update!(stripe_checkout_session_id: checkout_session.id)

      redirect_to checkout_session.url, allow_other_host: true
    end

    def success
      @production = @course_offering.production
      @person = Current.user.person

      # Find the registration - either by session_id or by person
      if params[:session_id].present?
        @registration = @course_offering.course_registrations
          .find_by(stripe_checkout_session_id: params[:session_id])
      end

      @registration ||= @course_offering.course_registrations
        .where(person: @person)
        .where.not(status: %w[cancelled refunded])
        .order(created_at: :desc)
        .first

      # If no registration found, redirect to the course page
      unless @registration
        redirect_to my_course_show_path(code: @course_offering.short_code)
        nil
      end
    end

    def inactive
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
  end
end
