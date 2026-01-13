# frozen_string_literal: true

class PostView < ApplicationRecord
  belongs_to :user
  belongs_to :post

  validates :user_id, uniqueness: { scope: :post_id }
  validates :viewed_at, presence: true

  # Mark a post as viewed by a user
  def self.mark_viewed(user:, post:)
    find_or_create_by!(user: user, post: post) do |view|
      view.viewed_at = Time.current
    end
  rescue ActiveRecord::RecordNotUnique
    # Race condition - record already exists, which is fine
    find_by(user: user, post: post)
  end

  # Check if a user has viewed a post
  def self.viewed?(user:, post:)
    exists?(user: user, post: post)
  end
end
