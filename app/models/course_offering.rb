# frozen_string_literal: true

class CourseOffering < ApplicationRecord
  belongs_to :production
  belongs_to :contract, optional: true
  belongs_to :instructor_person, class_name: "Person", optional: true
  belongs_to :questionnaire, optional: true
  belongs_to :feature_credit_redemption, optional: true
  has_many :course_registrations, dependent: :restrict_with_error
  has_one :email_draft, as: :emailable, dependent: :destroy

  has_one :organization, through: :production

  has_rich_text :description
  has_rich_text :instructor_bio

  has_one_attached :instructor_headshot

  enum :status, {
    draft: "draft",
    open: "open",
    closed: "closed",
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

  def sessions
    production.shows.order(:date_and_time)
  end

  def upcoming_sessions
    sessions.where("date_and_time >= ?", Time.current)
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
