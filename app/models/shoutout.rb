class Shoutout < ApplicationRecord
  # Polymorphic association for the recipient (person, group, and future: production, organization)
  belongs_to :shoutee, polymorphic: true

  # The person giving the shoutout
  belongs_to :author, class_name: "Person"

  # Validations
  validates :content, presence: true, length: { maximum: 2000 }
  validates :shoutee_id, presence: true
  validates :shoutee_type, presence: true
  validates :author_id, presence: true

  # Scopes
  scope :newest_first, -> { order(created_at: :desc) }
  scope :for_entity, ->(entity) { where(shoutee: entity) }
  scope :by_author, ->(author) { where(author: author) }

  # Returns a truncated preview of the content
  def preview(length: 150)
    content.truncate(length)
  end
end
