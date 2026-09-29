# frozen_string_literal: true

# Audit trail: a manager opened someone's W-9, which shows their full TIN.
class TaxDocumentAccess < ApplicationRecord
  belongs_to :organization
  # Nil once the user's account is deleted — the access is still on record.
  belongs_to :user, optional: true
  belongs_to :w9_submission
end
