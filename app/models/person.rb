class Person < ApplicationRecord
  belongs_to :user, optional: true
  has_many :audition_requests, dependent: :destroy
  has_many :auditions

  has_and_belongs_to_many :casts

  has_many :show_person_role_assignments, dependent: :destroy
  has_many :shows, through: :show_person_role_assignments
  has_many :roles, through: :show_person_role_assignments

  has_one_attached :resume, dependent: :purge_later
  has_one_attached :headshot, dependent: :purge_later do |attachable|
    attachable.variant :thumb, resize_to_limit: [ 100, 100 ], preprocessed: true
  end

  # Validations
  validates :name, presence: true
  validates :email, presence: true
  validate :resume_content_type
  validate :headshot_content_type

  def initials
    return "" if name.blank?
    name.split.map { |word| word[0] }.join.upcase
  end

  def has_person_role_assignment_for_show?(show)
    show_person_role_assignments.exists?(show: show)
  end

  private

  def resume_content_type
    if resume.attached? && !resume.content_type.in?(%w[application/pdf image/jpeg image/png])
      errors.add(:resume, "Resume must be a PDF, JPEG, or PNG file")
    end
  end

  def headshot_content_type
    if headshot.attached? && !headshot.content_type.in?(%w[image/jpeg image/png])
      errors.add(:headshot, "Headshot must be a JPEG or PNG file")
    end
  end
end
