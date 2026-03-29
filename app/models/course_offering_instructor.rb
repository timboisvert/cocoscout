# frozen_string_literal: true

class CourseOfferingInstructor < ApplicationRecord
  belongs_to :course_offering
  belongs_to :person

  has_one_attached :headshot

  validates :person_id, uniqueness: { scope: :course_offering_id }

  default_scope { order(:position) }
end
