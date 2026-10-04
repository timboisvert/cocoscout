# frozen_string_literal: true

# An organization's box office settings: whether it's switched on (a pilot
# flag a superadmin sets), its public address (/tickets/<slug>), and its defaults.
# No branding in v1 — every org gets the same standard pages.
class TicketingProfile < ApplicationRecord
  FEE_MODES = %w[buyer org].freeze
  # Automatic withdrawal of the CocoScout balance to the theater's bank. Off
  # by default: money left here pays payout runs without a bank debit.
  AUTO_WITHDRAW = %w[off weekly after_shows].freeze
  # Path words under /tickets that an org's slug must never shadow.
  RESERVED_SLUGS = %w[orders checkout embed embed-js v p go door api assets help admin].freeze

  belongs_to :organization
  has_many :short_links, as: :target, dependent: :destroy
  has_one :short_link, -> { canonical }, as: :target

  normalizes :slug, with: ->(s) { s.to_s.strip.downcase }
  normalizes :support_email, with: ->(e) { e.to_s.strip.downcase.presence }

  validates :slug, presence: true, uniqueness: true,
                   format: { with: /\A[a-z0-9][a-z0-9-]{1,48}[a-z0-9]\z/,
                             message: "can use lowercase letters, numbers and dashes" }
  validate :slug_not_reserved
  validates :default_fee_mode, inclusion: { in: FEE_MODES }
  validates :auto_withdraw, inclusion: { in: AUTO_WITHDRAW }
  validates :default_max_per_order, numericality: { only_integer: true, in: 1..100 }
  validates :support_email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_nil: true
  # Days before a show that buyers get their reminder; nil sends none.
  validates :reminder_days_before, numericality: { only_integer: true, in: 1..30 }, allow_nil: true

  before_validation :default_slug, on: :create
  after_create_commit { ShortLink.canonical_for!(self) }

  # The org's profile, created (switched off) the first time anyone asks.
  def self.for(organization)
    organization.ticketing_profile || organization.create_ticketing_profile!
  rescue ActiveRecord::RecordNotUnique
    organization.reload.ticketing_profile
  end

  private

  def default_slug
    return if slug.present?

    base = organization&.name.to_s.parameterize.first(40).delete_suffix("-").presence || "box-office"
    base = "#{base}-tickets" if RESERVED_SLUGS.include?(base) || base.length < 3
    candidate = base
    n = 1
    while self.class.exists?(slug: candidate)
      n += 1
      candidate = "#{base}-#{n}"
    end
    self.slug = candidate
  end

  def slug_not_reserved
    errors.add(:slug, "is reserved") if RESERVED_SLUGS.include?(slug)
  end
end
