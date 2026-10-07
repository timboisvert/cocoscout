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
  RESERVED_SLUGS = %w[orders checkout embed embed-js v p go door api assets help admin pass-checkout my-pass].freeze

  belongs_to :organization
  has_many :short_links, as: :target, dependent: :destroy
  has_one :short_link, -> { canonical }, as: :target

  normalizes :slug, with: ->(s) { s.to_s.strip.downcase }
  normalizes :support_email, with: ->(e) { e.to_s.strip.downcase.presence }

  validates :slug, presence: true, uniqueness: { message: "is already another box office's address" },
                   format: { with: /\A[a-z0-9][a-z0-9-]{1,48}[a-z0-9]\z/,
                             message: "can use lowercase letters, numbers and dashes" }
  validate :slug_not_reserved
  validate :slug_not_someone_elses_old_address
  validates :default_fee_mode, inclusion: { in: FEE_MODES }
  validates :auto_withdraw, inclusion: { in: AUTO_WITHDRAW }
  validates :default_max_per_order, numericality: { only_integer: true, in: 1..100 }
  validates :support_email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_nil: true
  # Days before a show that buyers get their reminder; nil sends none.
  validates :reminder_days_before, numericality: { only_integer: true, in: 1..30 }, allow_nil: true
  # The refund policy buyers see at checkout (RefundPolicy).
  validates :refund_policy, inclusion: { in: RefundPolicy::KINDS }
  validates :refund_window_hours, numericality: { only_integer: true, in: 0..RefundPolicy::MAX_HOURS }
  validates :refund_policy_note, length: { maximum: RefundPolicy::NOTE_LIMIT }

  def refund_policy_object
    RefundPolicy.of_profile(self)
  end

  before_validation :default_slug, on: :create
  # The address it's leaving keeps working (a redirect) and stays its own.
  before_update :remember_previous_slug, if: :will_save_change_to_slug?
  after_create_commit { ShortLink.canonical_for!(self) }

  # The org's profile, created (switched off) the first time anyone asks. Two
  # requests creating at once: the org's unique index keeps one; a theater
  # with the same name taking the address in that instant gets the next one.
  def self.for(organization)
    attempts = 0
    begin
      organization.ticketing_profile || organization.create_ticketing_profile!
    rescue ActiveRecord::RecordNotUnique
      existing = organization.reload.ticketing_profile
      return existing if existing

      attempts += 1
      retry if attempts < 3
      raise
    end
  end

  # The box office at an address: its current one, or one it used before
  # (moved: true, so the caller can redirect to the current address).
  def self.at_address(slug)
    slug = slug.to_s.downcase
    return nil if slug.blank?

    if (profile = find_by(slug: slug))
      [ profile, false ]
    elsif (profile = where("previous_slugs @> ?", [ slug ].to_json).first)
      [ profile, true ]
    end
  end

  def self.address_taken?(slug, except: nil)
    scope = except ? where.not(id: except.id) : all
    scope.where(slug: slug).or(scope.where("previous_slugs @> ?", [ slug ].to_json)).exists?
  end

  private

  def default_slug
    return if slug.present?

    base = organization&.name.to_s.parameterize.first(40).delete_suffix("-").presence || "box-office"
    base = "#{base}-tickets" if RESERVED_SLUGS.include?(base) || base.length < 3
    candidate = base
    n = 1
    while self.class.address_taken?(candidate)
      n += 1
      candidate = "#{base}-#{n}"
    end
    self.slug = candidate
  end

  def slug_not_reserved
    errors.add(:slug, "is reserved") if RESERVED_SLUGS.include?(slug)
  end

  def slug_not_someone_elses_old_address
    return if slug.blank?
    return unless self.class.where.not(id: id).where("previous_slugs @> ?", [ slug ].to_json).exists?

    errors.add(:slug, "is another box office's old address")
  end

  def remember_previous_slug
    old = slug_in_database
    self.previous_slugs = ((previous_slugs || []) | [ old ]) - [ slug ]
  end
end
