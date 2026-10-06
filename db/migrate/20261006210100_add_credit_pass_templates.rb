# frozen_string_literal: true

# The emails a credit pass's holder gets: the pass, and a reminder before it
# ends (TicketingTemplates).
class AddCreditPassTemplates < ActiveRecord::Migration[8.1]
  def up
    TicketingTemplates.ensure!(keys: %w[ticket_pass_bought ticket_pass_ending])
  end

  def down
    ContentTemplate.where(key: %w[ticket_pass_bought ticket_pass_ending]).destroy_all
  end
end
