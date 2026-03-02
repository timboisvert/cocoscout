# frozen_string_literal: true

module Manage
  class CourseOfferingsController < Manage::ManageController
    before_action :load_course_offering, only: %i[show edit update open_registration close_registration]

    def index
      @course_offerings = Current.organization.productions
        .courses
        .active
        .includes(:course_offerings)
        .flat_map(&:course_offerings)
        .sort_by(&:created_at)
        .reverse
    end

    def show
      @registrations = @course_offering.course_registrations
        .includes(:person)
        .order(registered_at: :desc)
      @sessions = @course_offering.sessions
    end

    def edit
    end

    def update
      if @course_offering.update(course_offering_params)
        redirect_to manage_course_offering_path(@course_offering), notice: "Course offering updated."
      else
        render :edit, status: :unprocessable_entity
      end
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

    private

    def load_course_offering
      @course_offering = CourseOffering.find(params[:id])
      # Verify it belongs to the current organization
      unless @course_offering.production.organization == Current.organization
        redirect_to manage_course_offerings_path, alert: "Course offering not found."
      end
    end

    def course_offering_params
      params.require(:course_offering).permit(
        :title, :subtitle, :description, :instructor_name, :instructor_bio,
        :price_cents, :early_bird_price_cents, :early_bird_deadline,
        :currency, :capacity, :opens_at, :closes_at,
        :instruction_text, :success_text
      )
    end
  end
end
