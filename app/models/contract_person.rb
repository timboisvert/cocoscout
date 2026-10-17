# frozen_string_literal: true

# Someone on a contract besides the contractor (docs/contract_people_plan.md,
# Tim 2026-10-17): the people a contractor brings. They get the contractor's
# visibility on My (My Contracts, Ticket Sales, their dates in My shows,
# comps) and nothing more: the Contractor stays the one party that signs and
# is paid, and nobody becomes a contract administrator by being added. Never
# a ProductionPermission.
class ContractPerson < ApplicationRecord
  belongs_to :contract
  belongs_to :person
  belongs_to :added_by, class_name: "User", optional: true

  validates :person_id, uniqueness: { scope: :contract_id }
end
