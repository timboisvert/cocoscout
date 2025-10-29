class Production < ApplicationRecord
    has_many :posters, dependent: :destroy
    has_many :shows, dependent: :destroy
    has_many :call_to_auditions, dependent: :destroy
    has_many :audition_requests, through: :call_to_auditions
    has_many :audition_sessions, dependent: :destroy
    has_many :casts, dependent: :destroy
    has_many :roles, dependent: :destroy
    has_many :show_person_role_assignments, through: :shows
    has_many :production_permissions, dependent: :destroy
    belongs_to :production_company

    has_one_attached :logo, dependent: :purge_later do |attachable|
        attachable.variant :small, resize_to_limit: [ 300, 200 ], preprocessed: true
    end

    normalizes :contact_email, with: ->(e) { e.strip.downcase }

    validates :name, presence: true
    validates :contact_email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
    validate :logo_content_type

    def initials
      return "" if name.blank?
      name.split.map { |word| word[0] }.join.upcase
    end

    def next_show
        shows.where("date_and_time > ?", Time.current).order(:date_and_time).first
    end

    def safe_logo_variant(variant_name)
        return nil unless logo.attached?
        logo.variant(variant_name)
    rescue ActiveStorage::InvariableError, ActiveStorage::FileNotFoundError => e
        Rails.logger.error("Failed to generate variant for production #{id} logo: #{e.message}")
        nil
    end

    private

    def logo_content_type
        if logo.attached? && !logo.content_type.in?(%w[image/jpeg image/jpg image/png])
            errors.add(:logo, "Logo must be a JPEG, JPG, or PNG file")
        end
    end
end
