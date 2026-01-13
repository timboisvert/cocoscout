# frozen_string_literal: true

class Post < ApplicationRecord
  belongs_to :production
  belongs_to :author, polymorphic: true
  belongs_to :parent, class_name: "Post", optional: true
  has_many :replies, class_name: "Post", foreign_key: :parent_id, dependent: :destroy
  has_many :post_views, dependent: :delete_all

  has_rich_text :body

  validates :body, presence: true

  scope :top_level, -> { where(parent_id: nil) }
  scope :recent_first, -> { order(created_at: :desc) }
  scope :oldest_first, -> { order(created_at: :asc) }
  scope :unviewed_by, ->(user) {
    where.not(id: PostView.where(user: user).select(:post_id))
  }

  # Author display name
  def author_name
    author.name
  end

  # Author initials for fallback avatar
  def author_initials
    author.initials
  end

  # Author headshot variant for display
  def author_headshot_variant(variant_name = :thumb)
    author.safe_headshot_variant(variant_name)
  end

  # Check if this is a reply
  def reply?
    parent_id.present?
  end

  # Count of replies
  def replies_count
    replies.count
  end

  # Check if this post has been viewed by the given user
  def viewed_by?(user)
    PostView.viewed?(user: user, post: self)
  end

  # Mark this post as viewed by the given user
  def mark_viewed_by(user)
    PostView.mark_viewed(user: user, post: self)
  end
end
