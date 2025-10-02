class Show < ApplicationRecord
  belongs_to :production
  belongs_to :location

  has_many :show_person_role_assignments, dependent: :destroy
  has_many :people, through: :show_person_role_assignments
  has_many :roles, through: :show_person_role_assignments

  has_one_attached :poster, dependent: :purge_later do |attachable|
      attachable.variant :small, resize_to_limit: [ 200, 300 ], preprocessed: true
  end

  validates :location, presence: true
  validate :poster_content_type

  def display_name
    "#{production.name} - #{secondary_name} - #{date_and_time.strftime("%-m/%-d/%Y")}"
  end

  private

  def poster_content_type
    if poster.attached? && !poster.content_type.in?(%w[image/jpeg image/jpg image/png])
      errors.add(:poster, "Poster must be a JPEG, JPG, or PNG file")
    end
  end
end
