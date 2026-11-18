# frozen_string_literal: true

# You issue a comp (Tim, 2026-11-17): the two notices about a comp said
# "gave" and "given". Their seeded words are replaced; ContentTemplate is
# the only table this reads.
class CompNoticesSayIssued < ActiveRecord::Migration[8.1]
  def up
    TicketingTemplates.ensure!(keys: %w[ticketing_comp_issued], overwrite: true)
    ContractConnectionTemplates.ensure!(keys: %w[linked_ticket_comp], overwrite: true)
  end

  def down; end
end
