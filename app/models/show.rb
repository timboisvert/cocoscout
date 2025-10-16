class Show < ApplicationRecord
  belongs_to :production
  belongs_to :location

  has_many :show_person_role_assignments, dependent: :destroy
  has_many :people, through: :show_person_role_assignments
  has_many :roles, through: :show_person_role_assignments

  has_many :show_links, dependent: :destroy
  accepts_nested_attributes_for :show_links, allow_destroy: true

  has_one_attached :poster, dependent: :purge_later do |attachable|
      attachable.variant :small, resize_to_limit: [ 200, 300 ], preprocessed: true
  end

  enum :event_type, {
    show: "show",
    rehearsal: "rehearsal",
    meeting: "meeting"
  }

  validates :location, presence: true
  validates :event_type, presence: true
  validate :poster_content_type

  # Scope to find all shows in a recurrence group
  scope :in_recurrence_group, ->(group_id) { where(recurrence_group_id: group_id) }

  # Check if this show is part of a recurring series
  def recurring?
    recurrence_group_id.present?
  end

  # Get all shows in the same recurrence group
  def recurrence_siblings
    return Show.none unless recurring?
    Show.in_recurrence_group(recurrence_group_id).where.not(id: id)
  end

  # Get all shows in the recurrence group including self
  def recurrence_group
    return Show.none unless recurring?
    Show.in_recurrence_group(recurrence_group_id)
  end

  private

  def poster_content_type
    if poster.attached? && !poster.content_type.in?(%w[image/jpeg image/jpg image/png])
      errors.add(:poster, "Poster must be a JPEG, JPG, or PNG file")
    end
  end
end
