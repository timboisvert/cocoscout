# frozen_string_literal: true

class Session < ApplicationRecord
  belongs_to :user
  # Set when a superadmin impersonates someone: the user who started it. Lives
  # on the session row (not a cookie) so the impersonation banner survives
  # anything the browser does to its session cookies.
  belongs_to :impersonator, class_name: "User", optional: true
  # The app's phone signed in here; signing out ends its notifications.
  has_many :device_tokens, dependent: :delete_all

  def label
    DeviceLabel.from_user_agent(user_agent)
  end

  # How this device got in, for the Account page: "with a password". nil for
  # sign-ins from before we kept it, so the page says nothing rather than guess.
  SIGN_IN_METHOD_WORDS = {
    "password" => "with a password",
    "code" => "with an emailed code",
    "reset_link" => "with a password link",
    "invitation" => "with an invitation"
  }.freeze

  def sign_in_method_words
    SIGN_IN_METHOD_WORDS[sign_in_method]
  end
end
