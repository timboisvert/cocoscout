# frozen_string_literal: true

# Claude and Copilot are development tools, a kind of cost of their own
# beside hosting: bills already read in as "software" move over.
class ClaudeAndCopilotAreDevelopmentCosts < ActiveRecord::Migration[8.1]
  def up
    execute "UPDATE company_expenses SET category = 'development' WHERE category = 'software' AND vendor IN ('Anthropic', 'GitHub')"
  end

  def down
    execute "UPDATE company_expenses SET category = 'software' WHERE category = 'development'"
  end
end
