class ProfileVideo < ApplicationRecord
  belongs_to :profileable, polymorphic: true

  # Enums
  enum :video_type, { youtube: 0, vimeo: 1, google_drive: 2, other: 3 }, default: :other

  # Validations
  validates :url, presence: true, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]), message: "must be a valid URL" }
  validates :title, length: { maximum: 100 }
  validates :position, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  # Scopes
  default_scope { order(:position) }

  # Callbacks
  before_validation :detect_video_type
  before_validation :set_default_position, on: :create

  private

  def detect_video_type
    return if url.blank?
    
    if url.include?("youtube.com") || url.include?("youtu.be")
      self.video_type = :youtube
    elsif url.include?("vimeo.com")
      self.video_type = :vimeo
    elsif url.include?("drive.google.com")
      self.video_type = :google_drive
    else
      self.video_type = :other
    end
  end

  def set_default_position
    return if position.present?
    max_position = profileable&.profile_videos&.maximum(:position) || -1
    self.position = max_position + 1
  end
end
