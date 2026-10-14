# frozen_string_literal: true

# Every message pushes; people choose what buzzes in their iPhone's own
# notification settings (Tim, 2026-10-13). Turns back on the seven templates
# 20261013120000 shipped quiet.
class PushEveryContentTemplate < ActiveRecord::Migration[8.1]
  def up
    execute "UPDATE content_templates SET push = TRUE WHERE push = FALSE"
  end

  def down
    # Nothing to restore: quiet templates were a default, not a choice anyone made.
  end
end
