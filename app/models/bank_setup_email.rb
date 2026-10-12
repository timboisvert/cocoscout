# frozen_string_literal: true

# One bank setup link emailed to a payee (BankSetupLink). The link itself is
# never stored or shown; this only lets the page say when it was sent.
class BankSetupEmail < ApplicationRecord
  belongs_to :organization
  belongs_to :payee, polymorphic: true
  belongs_to :sent_by, class_name: "User", optional: true

  validates :email, presence: true

  def self.last_for(organization, payee)
    where(organization: organization, payee: payee).order(:created_at).last
  end
end
