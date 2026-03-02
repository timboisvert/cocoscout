# frozen_string_literal: true

class CourseShortlinkController < ApplicationController
  allow_unauthenticated_access

  def show
    course_offering = CourseOffering.find_by!(short_code: params[:code].upcase)
    redirect_to my_course_entry_path(params[:code]), allow_other_host: false
  end
end
