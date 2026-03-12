# frozen_string_literal: true

class CocobaseSubmission < ApplicationRecord
  belongs_to :cocobase
  belongs_to :submittable, polymorphic: true
  has_many :cocobase_answers, dependent: :destroy

  enum :status, { pending: "pending", in_progress: "in_progress", submitted: "submitted" }, default: :pending

  validates :status, presence: true

  def submit!
    update!(status: :submitted, submitted_at: Time.current)
  end

  def cocobase_fields
    cocobase.cocobase_fields
  end

  def deadline
    cocobase.deadline
  end

  def past_deadline?
    cocobase.past_deadline?
  end

  def show
    cocobase.show
  end

  def production
    cocobase.show.production
  end
end
