class Production < ApplicationRecord
    has_many :shows, dependent: :destroy
    has_many :call_to_auditions, dependent: :destroy
    has_many :audition_sessions, dependent: :destroy
    has_many :casts, dependent: :destroy
    has_many :roles, dependent: :destroy
    has_many :posters, dependent: :destroy
    belongs_to :production_company

    has_one_attached :logo, dependent: :purge_later do |attachable|
        attachable.variant :small, resize_to_limit: [ 300, 200 ], preprocessed: true
    end

    def audition_requests(filter: "to_be_scheduled")
        ar = AuditionRequest.joins(:call_to_audition).where(call_to_auditions: { production_id: self.id })

        if filter == "all"
            ar = ar.where(status: [ :unreviewed, :undecided, :passed, :accepted ])
        elsif filter == "to_be_scheduled"
            ar = ar.where(status: :accepted).where.not(person_id: audition_sessions.joins(:auditions).select("auditions.person_id"))
        elsif filter == "accepted"
            ar = ar.where(status: :accepted)
        end

        ar.order(created_at: :asc)
    end
end
