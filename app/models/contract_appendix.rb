# frozen_string_literal: true

# A titled rich-text section appended to the end of a contract's body, above the
# signature block — a tech rider, a hospitality list. Part of what gets signed,
# and baked into the version snapshot at signing time, so editing one later can
# never change a document somebody already signed.
class ContractAppendix < ApplicationRecord
  belongs_to :contract
  has_rich_text :body

  validates :title, presence: true, length: { maximum: 150 }

  scope :ordered, -> { order(:position, :created_at) }

  # "Appendix A", "Appendix B"… by position among its siblings.
  def letter
    index = contract.contract_appendixes.ordered.index(self) || 0
    ("A".ord + index).chr
  end

  def heading
    "Appendix #{letter} — #{title}"
  end

  # to_html, never to_s: to_s renders through ApplicationController.renderer and
  # wraps the output in a trix-content div, which is fragile inside a job.
  def body_html
    body&.body&.to_html.to_s
  end
end
