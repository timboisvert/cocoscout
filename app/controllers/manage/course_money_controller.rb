# frozen_string_literal: true

module Manage
  # A course's full money statement — payments, refunds, fees, and payouts, each
  # traceable to its Stripe object. In Courses (a free module), not the Pro-only
  # Money section.
  class CourseMoneyController < Manage::ManageController
    before_action :load_course_offering

    def show
      @statement = CourseMoneyStatement.new(@course_offering)
    end

    private

    def load_course_offering
      @course_offering = CourseOffering.find(params[:course_offering_id]) # rubocop:disable CocoScout/UnscopedFind -- org ownership checked immediately below (production.organization)
      unless @course_offering.production.organization == Current.organization
        redirect_to manage_course_offerings_path, alert: "Course not found."
        return
      end
      @production = @course_offering.production
      return if Current.user.accessible_productions.include?(@production)

      redirect_to manage_course_offerings_path, alert: "You do not have access to this course."
    end
  end
end
