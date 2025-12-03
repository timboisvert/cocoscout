class Production < ApplicationRecord
    # Delete cast_assignment_stages first since they reference both audition_cycles and talent_pools
    before_destroy :delete_cast_assignment_stages
    before_destroy :delete_people_talent_pools_joins

    has_many :posters, dependent: :destroy
    has_many :shows, dependent: :destroy
    has_many :audition_cycles, dependent: :destroy
    has_many :audition_requests, through: :audition_cycles
    has_many :talent_pools, dependent: :delete_all
    has_many :roles, dependent: :delete_all
    has_many :show_person_role_assignments, through: :shows
    has_many :production_permissions, dependent: :delete_all
    has_many :questionnaires, dependent: :destroy
    belongs_to :organization

    has_one_attached :logo, dependent: :purge_later do |attachable|
        attachable.variant :small, resize_to_limit: [ 300, 200 ], preprocessed: true
    end

    normalizes :contact_email, with: ->(e) { e.strip.downcase }

    validates :name, presence: true
    validates :contact_email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
    validate :logo_content_type

    # Cache invalidation
    after_commit :invalidate_caches

    def active_audition_cycle
        audition_cycles.find_by(active: true)
    end

    # For backwards compatibility during transition
    def audition_cycle
        active_audition_cycle
    end

    def audition_sessions
        active_audition_cycle&.audition_sessions || AuditionSession.none
    end

    def cast_assignment_stages
        active_audition_cycle&.cast_assignment_stages || CastAssignmentStage.none
    end

    def initials
      return "" if name.blank?
      name.split.map { |word| word[0] }.join.upcase
    end

    def next_show
        shows.where("date_and_time > ?", Time.current).order(:date_and_time).first
    end

    def primary_poster
        posters.find_by(is_primary: true)
    end

    # Cached count of roles for this production
    # Used in cast percentage calculations and other aggregate views
    def cached_roles_count
        Rails.cache.fetch(["production_roles_count_v1", id, roles.maximum(:updated_at)], expires_in: 30.minutes) do
            roles.count
        end
    end

    def safe_logo_variant(variant_name)
        return nil unless logo.attached?
        logo.variant(variant_name)
    rescue ActiveStorage::InvariableError, ActiveStorage::FileNotFoundError => e
        Rails.logger.error("Failed to generate variant for production #{id} logo: #{e.message}")
        nil
    end

    def invalidate_caches
        # Invalidate dashboard cache
        Rails.cache.delete("production_dashboard_#{id}")
        # Invalidate roles count cache - use explicit key pattern
        # The cache key is: ["production_roles_count_v1", id, roles.maximum(:updated_at)]
        # Since we can't predict the timestamp, we need a different approach
        # Touch updated_at to invalidate via cache key versioning
    end

    private

    def delete_cast_assignment_stages
        # Delete all cast_assignment_stages for all audition_cycles in this production
        CastAssignmentStage.where(audition_cycle_id: audition_cycles.pluck(:id)).delete_all
    end

    def delete_people_talent_pools_joins
        # Delete all entries in the people_talent_pools join table for this production's talent pools
        ActiveRecord::Base.connection.execute(
            "DELETE FROM people_talent_pools WHERE talent_pool_id IN (SELECT id FROM talent_pools WHERE production_id = #{id})"
        )

        # Delete all auditions before deleting audition_requests or audition_sessions
        # Auditions reference both audition_requests and audition_sessions
        audition_session_ids = AuditionSession.joins(:audition_cycle).where(audition_cycles: { production_id: id }).pluck(:id)
        Audition.where(audition_session_id: audition_session_ids).delete_all
    end

    def logo_content_type
        if logo.attached? && !logo.content_type.in?(%w[image/jpeg image/jpg image/png])
            errors.add(:logo, "Logo must be a JPEG, JPG, or PNG file")
        end
    end
end
