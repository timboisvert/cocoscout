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

  # Public methods
  def embed_html
    case video_type&.to_sym
    when :youtube
      video_id = extract_youtube_id
      return nil unless video_id
      %(<iframe width="100%" height="100%" src="https://www.youtube.com/embed/#{video_id}" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture" allowfullscreen></iframe>)
    when :vimeo
      video_id = extract_vimeo_id
      return nil unless video_id
      %(<iframe src="https://player.vimeo.com/video/#{video_id}" width="100%" height="100%" frameborder="0" allow="autoplay; fullscreen; picture-in-picture" allowfullscreen></iframe>)
    when :google_drive
      file_id = extract_google_drive_id
      return nil unless file_id
      %(<iframe src="https://drive.google.com/file/d/#{file_id}/preview" width="100%" height="100%" allow="autoplay"></iframe>)
    else
      nil
    end
  end

  def platform
    case video_type&.to_sym
    when :youtube then "YouTube"
    when :vimeo then "Vimeo"
    when :google_drive then "Google Drive"
    else "External"
    end
  end

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

  def extract_youtube_id
    return nil if url.blank?

    # Handle various YouTube URL formats
    if url.include?("youtube.com/watch")
      uri = URI.parse(url)
      CGI.parse(uri.query)["v"]&.first
    elsif url.include?("youtu.be/")
      url.split("youtu.be/").last.split("?").first
    elsif url.include?("youtube.com/embed/")
      url.split("embed/").last.split("?").first
    end
  rescue
    nil
  end

  def extract_vimeo_id
    return nil if url.blank?

    # Extract Vimeo video ID from various formats
    match = url.match(%r{vimeo\.com/(?:video/)?(\d+)})
    match&.[](1)
  rescue
    nil
  end

  def extract_google_drive_id
    return nil if url.blank?

    # Extract Google Drive file ID from various formats
    if url.include?("/file/d/")
      url.split("/file/d/").last.split("/").first
    elsif url.include?("id=")
      uri = URI.parse(url)
      CGI.parse(uri.query)["id"]&.first
    end
  rescue
    nil
  end
end
