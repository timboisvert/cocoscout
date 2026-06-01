# frozen_string_literal: true

# We now publish only 4 mic formats: standup (0), music (1), poetry (2),
# open_stage (3). Any pre-existing values in 3..9 collapse into open_stage.
class SimplifyMicFormats < ActiveRecord::Migration[8.1]
  def up
    execute "UPDATE mics SET format = 3 WHERE format >= 3"
  end

  def down
    # No-op: collapsing values is one-way.
  end
end
