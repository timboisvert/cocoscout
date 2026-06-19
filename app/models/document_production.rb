# frozen_string_literal: true

# Links a ProductionDocument to a production it applies to. The document's
# primary `production_id` is always present here too; additional rows let one
# document apply to several productions at once.
class DocumentProduction < ApplicationRecord
  belongs_to :production_document
  belongs_to :production

  validates :production_id, uniqueness: { scope: :production_document_id }
end
