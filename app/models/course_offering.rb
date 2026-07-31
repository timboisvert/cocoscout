# frozen_string_literal: true

class CourseOffering < ApplicationRecord
  belongs_to :production
  belongs_to :contract, optional: true
  belongs_to :instructor_person, class_name: "Person", optional: true
  belongs_to :questionnaire, optional: true
  belongs_to :feature_credit_redemption, optional: true
  belongs_to :created_by_user, class_name: "User", optional: true
  has_many :course_registrations, dependent: :restrict_with_error
  has_many :course_offering_instructors, dependent: :destroy
  has_one :course_offering_payout, dependent: :destroy
  has_many :org_payouts, dependent: :nullify
  has_many :instructor_people, through: :course_offering_instructors, source: :person
  has_one :email_draft, as: :emailable, dependent: :destroy

  has_one :organization, through: :production

  has_rich_text :description
  has_rich_text :instructor_bio
  has_rich_text :instructor_preface

  has_one_attached :instructor_headshot
  has_one_attached :group_photo

  enum :status, {
    draft: "draft",
    open: "open",
    closed: "closed",
    completed: "completed",
    archived: "archived"
  }, default: :draft

  validates :short_code, presence: true, uniqueness: true
  validates :title, presence: true
  validates :price_cents, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :early_bird_price_cents, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :capacity, numericality: { greater_than: 0 }, allow_nil: true
  validates :currency, presence: true

  before_validation :generate_short_code, on: :create
  after_create :ensure_instructor_role
  after_commit :provision_stripe_resources_if_needed, on: %i[create update]

  scope :active, -> { where(status: %w[open closed]) }
  scope :accepting, -> { open }
  scope :listed, -> { where(listed_in_directory: true) }

  # --- Pricing ---

  def current_price_cents
    early_bird_active? ? early_bird_price_cents : price_cents
  end

  def early_bird_active?
    early_bird_price_cents.present? &&
      early_bird_deadline.present? &&
      Time.current < early_bird_deadline
  end

  def formatted_price
    format_cents(price_cents)
  end

  def formatted_early_bird_price
    return nil unless early_bird_price_cents.present?
    format_cents(early_bird_price_cents)
  end

  def formatted_current_price
    format_cents(current_price_cents)
  end

  # --- Capacity ---

  def confirmed_registrations_count
    course_registrations.where(status: :confirmed).count
  end

  # Money in (registrations) − money out (platform fee + instructor payouts) =
  # profit. All values in cents. The single source of truth for course money,
  # used by the money hub and the financials screens.
  def financials_summary
    confirmed = course_registrations.confirmed
    refunded = course_registrations.refunded
    # Refunded registrations already leave the `confirmed` scope, so the money we
    # actually kept is just the confirmed sum — don't subtract refunds again.
    gross_cents = confirmed.sum(:amount_cents)
    owed_cents = OrgPayout.owed_cents_for_course(self)
    payout_cents = course_offering_payout&.line_items&.sum(:amount_cents).to_i

    {
      confirmed_count: confirmed.count,
      refunded_count: refunded.count,
      gross_cents: gross_cents,
      owed_cents: owed_cents,
      fee_cents: gross_cents - owed_cents,
      payout_cents: payout_cents,
      net_cents: payout_cents.positive? ? owed_cents - payout_cents : owed_cents
    }
  end

  # Effective count includes confirmed registrations PLUS
  # temporary Redis spot holds (people currently on Stripe checkout).
  def effective_registrations_count
    confirmed_registrations_count + CourseSpotHoldService.active_holds_count(id)
  end

  def spots_remaining
    return nil unless capacity.present?
    [ capacity - effective_registrations_count, 0 ].max
  end

  def full?
    capacity.present? && effective_registrations_count >= capacity
  end

  # --- Registration status ---

  def accepting_registrations?
    open? &&
      !full? &&
      (opens_at.nil? || Time.current >= opens_at) &&
      (closes_at.nil? || Time.current <= closes_at)
  end

  def registration_closed_reason
    return nil if accepting_registrations?
    return "Registration is not yet open" unless open?
    return "This course is full" if full?
    return "Registration has not started yet" if opens_at.present? && Time.current < opens_at
    return "Registration has closed" if closes_at.present? && Time.current > closes_at
    "Registration is currently closed"
  end

  # --- Short URL ---

  def short_url_path
    "/c/#{short_code}"
  end

  # --- Course sessions (shows) ---

  # Sessions belonging to THIS run only. A course production can hold multiple
  # runs (offerings); each session (Show, event_type "class") is scoped by
  # course_offering_id so one run never shows another run's sessions.
  def sessions
    production.shows.where(course_offering_id: id).order(:date_and_time)
  end

  def upcoming_sessions
    sessions.where("date_and_time >= ?", Time.current)
  end

  # --- Instructors ---

  def instructor_names
    instructor_people.map(&:name).join(", ")
  end

  private

  def generate_short_code
    return if short_code.present?
    self.short_code = ShortKeyService.generate(type: :course)
  end

  def ensure_instructor_role
    production.roles.find_or_create_by!(name: "Instructor") do |role|
      role.category = "technical"
      role.quantity = 1
    end
  end

  # Safety net: any path that lands an offering in :open without Stripe set up
  # provisions resources here. The service is idempotent and only creates what's
  # missing, so it's safe alongside controller paths that call it explicitly.
  def provision_stripe_resources_if_needed
    return unless open?
    return if stripe_price_id.present? && stripe_product_id.present?
    return if Stripe.api_key.blank? # safety for test / non-Stripe environments

    CourseOfferingStripeService.new(self).ensure_stripe_resources!
  rescue CourseOfferingStripeService::StripeError => e
    Rails.logger.error "[CourseOffering #{id}] Failed to provision Stripe resources: #{e.message}"
  end

  def format_cents(cents)
    return "$0" if cents.nil? || cents.zero?
    dollars = cents / 100.0
    if dollars == dollars.to_i
      "$#{dollars.to_i}"
    else
      "$#{'%.2f' % dollars}"
    end
  end
end
