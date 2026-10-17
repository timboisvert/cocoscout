# frozen_string_literal: true

# An organization's box office settings: whether it's switched on (a pilot
# flag a superadmin sets), its public address (/tickets/<slug>), and its defaults.
# No branding in v1 — every org gets the same standard pages.
class TicketingProfile < ApplicationRecord
  FEE_MODES = %w[buyer org].freeze
  # Automatic withdrawal of the CocoScout balance to the theater's bank. Off
  # by default: money left here pays payout runs without a bank debit.
  AUTO_WITHDRAW = %w[off weekly after_shows].freeze
  # When the Door shows in the CocoScout app's menu (Ticketing settings →
  # Door): "smart" while a show is on (DoorTonight), or "always". Smart opens
  # door_hours_before the show, or the morning of show day when that's blank.
  DOOR_IN_APP = %w[smart always].freeze
  DOOR_HOURS_BEFORE = [ 1, 2, 3, 4, 6, 8, 12 ].freeze
  # Path words under /tickets that an org's slug must never shadow.
  RESERVED_SLUGS = %w[orders checkout embed embed-js v p go door api assets help admin pass-checkout my-pass].freeze
  # Who sees sales (Ticketing settings → Who sees sales), by role
  # (TicketSalesAccess): a production team manager sees everything (who's
  # coming by name, comps too), the numbers and the link, or nothing; a
  # production team viewer the numbers or nothing; the cast the count and
  # the link for every date of their production, only the dates they're
  # cast in, or nothing.
  TEAM_MANAGER_SALES = %w[everything numbers nothing].freeze
  TEAM_VIEWER_SALES = %w[numbers nothing].freeze
  CAST_SALES = %w[production_cast show_cast nothing].freeze
  # The comp rules (Ticketing settings → Comps): how many comps a date can
  # give away in all, and how many of them its production team may give.
  COMPS_LIMITS = %w[unlimited fixed per_performer].freeze
  TEAM_COMPS_LIMITS = %w[all fixed per_performer].freeze

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
  validates :door_in_app, inclusion: { in: DOOR_IN_APP }
  validates :door_hours_before, inclusion: { in: DOOR_HOURS_BEFORE }, allow_nil: true
  validates :team_manager_sales, inclusion: { in: TEAM_MANAGER_SALES }
  validates :team_viewer_sales, inclusion: { in: TEAM_VIEWER_SALES }
  validates :cast_sales, inclusion: { in: CAST_SALES }
  include CompRules
  validates :comps_limit, inclusion: { in: COMPS_LIMITS }
  validates :team_comps_limit, inclusion: { in: TEAM_COMPS_LIMITS }
  validates :comps_per_show, :team_comps_per_show, numericality: { only_integer: true, in: 0..10_000 }

  # What a production team role sees of its productions' sales.
  def team_level(role)
    case role
    when "manager" then { "everything" => :full, "numbers" => :numbers }[team_manager_sales]
    when "viewer" then (:numbers if team_viewer_sales == "numbers")
    end
  end

  # What the cast sees: the count and the link, or nothing.
  def cast_level
    :numbers unless cast_sales == "nothing"
  end

  # Who sees sales, read back in one sentence.
  def sharing_words
    manager = { "everything" => "everything", "numbers" => "the numbers and the link", "nothing" => "nothing" }[team_manager_sales]
    viewer = { "numbers" => "the numbers and the link", "nothing" => "nothing" }[team_viewer_sales]
    cast = { "production_cast" => "everyone on a production sees its dates' counts and links",
             "show_cast" => "the cast of each date sees its count and link",
             "nothing" => "the cast sees no ticket numbers" }[cast_sales]
    "Production team managers see #{manager}, production team viewers #{viewer}, and #{cast}."
  end

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
