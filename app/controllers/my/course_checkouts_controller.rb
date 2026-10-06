# frozen_string_literal: true

module My
  # Paying for a course on our own page, the way tickets are bought: the
  # registration holds the spot for ten minutes (CourseCheckout), Stripe's
  # Payment Element takes the card, and the done page settles the
  # registration itself (CourseCheckoutSettlement) without waiting for the
  # webhook. A free course settles on the spot.
  class CourseCheckoutsController < ApplicationController
    include CourseStorefront

    MIN_SECONDS_TO_PAY = 3

    # A visitor is sent to the course page (with its account step), not the
    # app's sign-in.
    allow_unauthenticated_access
    before_action :ensure_user_is_signed_in
    before_action :ensure_course_is_open, only: :create
    before_action :set_registration, except: :create

    # "Register": hold the spot, then the checkout page.
    def create
      registration = CourseCheckout.start!(offering: @course_offering, user: Current.user)
      redirect_to my_course_checkout_show_path(code: @course_offering.short_code, token: registration.token)
    rescue CourseCheckout::Error => e
      redirect_to my_course_show_path(code: @course_offering.short_code), alert: e.message
    end

    def show
      return redirect_to(my_course_success_path(code: @course_offering.short_code, token: @registration.token)) if @registration.confirmed?

      @expired = @registration.hold_expired? || !@registration.pending?
      @person = Current.user.person
    end

    # Finish a free registration, or hand back the PaymentIntent's client
    # secret for Stripe to confirm.
    def pay
      return render(json: { redirect: my_course_success_path(code: @course_offering.short_code, token: @registration.token) }) if @registration.confirmed?
      return render(json: { error: "Your hold on your spot ran out. Please start again." }, status: :unprocessable_content) if @registration.hold_expired? || !@registration.pending?
      return render(json: { error: "Please try again." }, status: :unprocessable_content) unless human_pace?

      if @registration.total_cents.zero?
        CourseCheckoutSettlement.settle!(@registration)
        return render(json: { redirect: my_course_success_path(code: @course_offering.short_code, token: @registration.token) })
      end

      render json: { client_secret: payment_intent.client_secret }
    rescue Stripe::StripeError => e
      Rails.logger.error("[CourseCheckouts] registration #{@registration.id}: #{e.message}")
      render json: { error: "We couldn't reach our payment processor. Please try again." }, status: :bad_gateway
    end

    # Stripe sends the student back here. The webhook is the source of truth,
    # but settle now too so the page tells the truth straight away.
    def done
      if @registration.stripe_payment_intent_id.present? && !@registration.confirmed?
        intent = Stripe::PaymentIntent.retrieve(@registration.stripe_payment_intent_id)
        if intent.status == "succeeded"
          CourseCheckoutSettlement.settle!(@registration, payment_intent_id: intent.id, charge_id: intent.latest_charge)
        elsif intent.status == "requires_payment_method"
          return redirect_to(my_course_checkout_show_path(code: @course_offering.short_code, token: @registration.token),
                             alert: "That payment didn't go through. Please try another way to pay.")
        end
      end
      redirect_to my_course_success_path(code: @course_offering.short_code, token: @registration.token)
    rescue Stripe::StripeError => e
      Rails.logger.error("[CourseCheckouts] done for registration #{@registration.id}: #{e.message}")
      redirect_to my_course_success_path(code: @course_offering.short_code, token: @registration.token)
    end

    private

    # The shared payment box tells a superadmin (or anyone in development)
    # when Stripe's publishable key is missing.
    def superadmin_viewer?
      authenticated? && Current.user&.superadmin?
    end
    helper_method :superadmin_viewer?

    # The token is the key, and it's the signed-in person's own.
    def set_registration
      @registration = @course_offering.course_registrations.find_by!(token: params[:token], person: Current.user.person)
    end

    # The honeypot is empty and the student spent a human amount of time here.
    def human_pace?
      if params[:website].present?
        Rails.logger.warn("[CourseCheckouts] honeypot tripped registration=#{@registration.id} ip=#{request.remote_ip}")
        return false
      end
      @registration.created_at <= MIN_SECONDS_TO_PAY.seconds.ago
    end

    # One PaymentIntent per registration, reused if they try again, re-priced
    # if the amount moved.
    def payment_intent
      if @registration.stripe_payment_intent_id.present?
        intent = Stripe::PaymentIntent.retrieve(@registration.stripe_payment_intent_id)
        return intent if intent.amount == @registration.total_cents && %w[requires_payment_method requires_confirmation requires_action].include?(intent.status)
      end

      organization_id = @course_offering.production.organization_id
      intent = Stripe::PaymentIntent.create(
        {
          amount: @registration.total_cents, currency: @registration.currency.presence || "usd",
          automatic_payment_methods: { enabled: true },
          description: "#{@course_offering.title} · #{@storefront_organization.name}",
          metadata: { type: "course_registration", course_registration_id: @registration.id, course_offering_id: @course_offering.id,
                      person_id: @registration.person_id, organization_id: organization_id },
          transfer_group: "org_#{organization_id}"
        },
        { idempotency_key: "course-registration-#{@registration.id}-#{@registration.total_cents}" }
      )
      @registration.update!(stripe_payment_intent_id: intent.id)
      intent
    end
  end
end
