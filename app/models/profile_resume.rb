class ProfileResume < ApplicationRecord
  include HierarchicalStorageKey

  belongs_to :profileable, polymorphic: true
  has_one_attached :file

  validate :acceptable_file
  validates :name, presence: true, length: { maximum: 100 }
  validates :position, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  default_scope { order(:position) }

  before_validation :set_default_position, on: :create
  before_validation :set_default_name, on: :create

  private

  def set_default_position
    return if position.present?
    max_position = profileable&.profile_resumes&.maximum(:position) || -1
    self.position = max_position + 1
  end

  def set_default_name
    return if name.present?
    return unless file.attached?
    self.name = file.filename.to_s
  end

  def acceptable_file
    return unless file.attached?
    unless file.content_type.in?(%w[application/pdf image/jpeg image/jpg image/png])
      errors.add(:file, "must be a PDF, JPG, or PNG file")
    end
  end
end
