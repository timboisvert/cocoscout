# frozen_string_literal: true

# One audience grant on a ProductionDocument with a read/write permission.
# A document is visible to a person if ANY share matches them; they can edit it
# if a matching share grants `write`.
#
#   team        -> people with a permission on the document's production
#   talent_pool -> members of talent pool #audience_id
#   person      -> person #audience_id
class DocumentShare < ApplicationRecord
  AUDIENCES = %w[team talent_pool person].freeze
  SCOPED    = %w[talent_pool person].freeze # audiences that carry an audience_id

  belongs_to :production_document

  enum :permission, { read: 0, write: 1 }, default: :read

  validates :audience_type, inclusion: { in: AUDIENCES }
  validates :audience_id, presence: true,  if: -> { audience_type.in?(SCOPED) }
  validates :audience_id, absence: true, unless: -> { audience_type.in?(SCOPED) }
end
