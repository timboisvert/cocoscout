# frozen_string_literal: true

# Someone who asked to hear from an organization (Mailing lists, V1.1). One
# row per person per organization: each organization keeps its own copy, with
# its own consent, unsubscribe state and history. Never "fan" or
# "subscriber" (Tim, 2026-10-23).
class Follower < ApplicationRecord
  STATUSES = %w[subscribed unsubscribed bounced complained].freeze

  belongs_to :organization
  belongs_to :person, optional: true
  has_many :follower_sources, dependent: :destroy
  has_many :mailing_list_memberships, dependent: :destroy
  has_many :mailing_lists, through: :mailing_list_memberships
  has_many :follower_email_deliveries, dependent: :destroy

  normalizes :email, with: ->(email) { email.to_s.strip.downcase }
  normalizes :name, with: ->(name) { name.to_s.squish.presence }

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }, uniqueness: { scope: :organization_id }
  validates :status, inclusion: { in: STATUSES }

  before_validation :ensure_unsubscribe_token
  before_create :link_person

  scope :subscribed, -> { where(status: "subscribed") }
  scope :not_suppressed, -> { where.not(email: EmailSuppression.select(:email)) }
  # Who an email can go to: still following and never bounced or complained anywhere.
  scope :emailable, -> { subscribed.not_suppressed }

  def subscribed? = status == "subscribed"

  def emailable?
    subscribed? && !EmailSuppression.suppressed?(email)
  end

  def first_name
    name.to_s.split.first
  end

  def display_name
    name.presence || email
  end

  def unsubscribe!
    return if status == "unsubscribed"

    update!(status: "unsubscribed", unsubscribed_at: Time.current)
  end

  def resubscribe!
    update!(status: "subscribed", unsubscribed_at: nil)
  end

  # The organization's follower for an email address, made if it's new. A
  # name fills in only when we didn't have one.
  # consented: false for a buyer who ticked nothing (we keep what they
  # bought, but they never agreed to hear from anyone).
  def self.for!(organization, email, name: nil, consented: true)
    follower = organization.followers.find_or_initialize_by(email: email.to_s.strip.downcase)
    follower.name = name if follower.name.blank? && name.present?
    follower.consented_at ||= Time.current if consented
    follower.save! if follower.changed?
    follower
  rescue ActiveRecord::RecordNotUnique
    organization.followers.find_by!(email: email.to_s.strip.downcase)
  end

  private

  def ensure_unsubscribe_token
    self.unsubscribe_token ||= SecureRandom.urlsafe_base64(24)
  end

  # A follower whose email belongs to someone in the organization wears the
  # CocoScout badge.
  def link_person
    return if person_id.present?

    self.person = organization.people.where("LOWER(people.email) = ?", email).order(Arel.sql("people.user_id IS NULL")).first
  end
end
