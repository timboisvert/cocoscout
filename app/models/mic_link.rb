# frozen_string_literal: true

# A URL associated with a mic — signup form, IG profile, venue page, etc.
class MicLink < ApplicationRecord
  belongs_to :mic

  # The "Socials" surface: we only support these four publicly. Older
  # rows imported with other types still exist in the DB but won't be
  # creatable via the UI; the detail page renders the type label as-is.
  enum :link_type, {
    website: 1,
    instagram: 2,
    tiktok: 4,
    x_twitter: 5
  }, prefix: :type

  validates :url, presence: true, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]) }

  scope :ordered, -> { order(:sort_order, :id) }
end
