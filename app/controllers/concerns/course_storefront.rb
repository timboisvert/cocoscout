# frozen_string_literal: true

# The public course pages (My::CourseRegistrationsController and
# My::CourseCheckoutsController): the storefront's layout, the course by its
# short code, and the account a student keeps.
module CourseStorefront
  extend ActiveSupport::Concern

  included do
    skip_before_action :show_my_sidebar
    layout "storefront"
    before_action :load_course_offering
    before_action :set_storefront
  end

  private

  def load_course_offering
    @course_offering = CourseOffering.find_by!(short_code: params[:code].to_s.upcase)
  rescue ActiveRecord::RecordNotFound
    redirect_to root_path, alert: "Course not found."
  end

  def set_storefront
    @production = @course_offering.production
    @storefront_organization = @production.organization
    @storefront_sold_line = "Classes by #{@storefront_organization.name}"
    @storefront_brand = "Class registration by CocoScout"
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
