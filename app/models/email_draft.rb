class EmailDraft < ApplicationRecord
  belongs_to :emailable, polymorphic: true, optional: true

  has_rich_text :body

  validates :title, presence: true
  validates :body, presence: true
end
