# frozen_string_literal: true

class Session < ApplicationRecord
  belongs_to :user
  # Set when a superadmin impersonates someone: the user who started it. Lives
  # on the session row (not a cookie) so the impersonation banner survives
  # anything the browser does to its session cookies.
  belongs_to :impersonator, class_name: "User", optional: true
end
