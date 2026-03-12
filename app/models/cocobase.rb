# frozen_string_literal: true

class Cocobase < ApplicationRecord
  belongs_to :show
  belongs_to :cocobase_template, optional: true
  has_many :cocobase_fields, -> { order(:position) }, dependent: :destroy
  has_many :cocobase_submissions, dependent: :destroy

  enum :status, { open: "open", closed: "closed" }, default: :open

  validates :status, presence: true

  def past_deadline?
    deadline.present? && deadline < Time.current
  end

  def submission_for(entity)
    cocobase_submissions.find_by(submittable: entity)
  end

  def submissions_count
    cocobase_submissions.count
  end

  def submitted_count
    cocobase_submissions.where(status: :submitted).count
  end

  def completion_summary
    total = submissions_count
    submitted = submitted_count
    { total: total, submitted: submitted, pending: total - submitted }
  end
end
