# frozen_string_literal: true

# DemoUser stores emails of users who should be added as managers
# to the demo organization when the demo seed runs. These records
# persist across demo seed resets.
class DemoUser < ApplicationRecord
  belongs_to :created_by, class_name: "User", optional: true

  validates :email, presence: true, uniqueness: { case_sensitive: false }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP, message: "must be a valid email address" }

  normalizes :email, with: ->(email) { email.strip.downcase }

  scope :ordered, -> { order(:email) }

  # Find the actual User record for this demo user email
  def user
    User.find_by(email_address: email)
  end

  # Check if this demo user has created an account
  def registered?
    user.present?
  end
end
