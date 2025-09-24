class Production < ApplicationRecord
    has_many :shows, dependent: :destroy
    has_many :call_to_auditions, dependent: :destroy
    has_many :audition_requests, through: :call_to_auditions
    has_many :audition_sessions, dependent: :destroy
    has_many :casts, dependent: :destroy
    has_many :roles, dependent: :destroy
    has_many :posters, dependent: :destroy
    belongs_to :production_company

    has_one_attached :logo, dependent: :purge_later do |attachable|
        attachable.variant :small, resize_to_limit: [ 300, 200 ], preprocessed: true
    end
end
