# frozen_string_literal: true

# A single party's e-signature on a contract, mirroring AgreementSignature's
# audit fields (signed_at / ip_address / user_agent / content_snapshot /
# template_version) for legal durability.
#
# Two roles sign a contract:
#   organization — stamped when the producer sends it (the org's assent)
#   contractor   — stamped when the counterparty agrees on the public sign page
#
# The signer is captured by free text (signer_name/email) so a contractor without
# a CocoScout login can still sign; person/signed_by_user link it to a record when
# one exists.
class ContractSignature < ApplicationRecord
  belongs_to :contract
  belongs_to :person, optional: true
  belongs_to :signed_by_user, class_name: "User", optional: true
  belongs_to :contract_template, optional: true

  enum :signer_role, {
    organization: "organization",
    contractor: "contractor"
  }, prefix: :role

  validates :signed_at, presence: true
  validates :content_snapshot, presence: true

  scope :recent, -> { order(signed_at: :desc) }

  # e.g. "July 27, 2026"
  def signed_on
    signed_at.strftime("%B %-d, %Y")
  end

  # e.g. "July 27, 2026 at 2:32 PM"
  def signed_at_long
    signed_at.strftime("%B %-d, %Y at %-l:%M %p")
  end
end
