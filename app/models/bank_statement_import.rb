# frozen_string_literal: true

# One statement file brought in (Books V1.3, plan D3). The file is read once
# in the request and never kept (§9.13): this row remembers its name, its
# dates and its closing balance, and its lines are BankStatementLines.
class BankStatementImport < ApplicationRecord
  FORMATS = %w[csv ofx].freeze

  belongs_to :organization
  belongs_to :imported_by, class_name: "User", optional: true
  has_many :bank_statement_lines, dependent: :destroy

  validates :format, inclusion: { in: FORMATS }

  def title
    return filename.presence || "Statement" unless from_on && to_on

    from_on.year == to_on.year && from_on.month == to_on.month ? from_on.strftime("%B %Y") : "#{from_on.strftime('%b %-d')} to #{to_on.strftime('%b %-d, %Y')}"
  end
end
