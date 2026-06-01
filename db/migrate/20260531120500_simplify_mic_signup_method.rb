# frozen_string_literal: true

# The signup_method enum was too granular and overlapped with what's
# really a secondary attribute (bucket draw). We collapse it to three
# primary values: online | in_person | online_and_in_person, and add a
# separate boolean `bucket_draw` that can be set on any of them.
#
# Old value → new value (and bucket_draw):
#   0 bucket_draw    → in_person                 (1) + bucket_draw=true
#   1 pre_signup     → online                    (0)
#   2 walk_up        → in_person                 (1)
#   3 lottery_online → online                    (0)
#   4 invite_only    → NULL (unknown; rare)
#   5 hybrid         → online_and_in_person      (2)
class SimplifyMicSignupMethod < ActiveRecord::Migration[8.1]
  def up
    add_column :mics, :bucket_draw, :boolean, null: false, default: false
    execute "UPDATE mics SET bucket_draw = true WHERE signup_method = 0"
    execute <<~SQL
      UPDATE mics SET signup_method = CASE
        WHEN signup_method = 0 THEN 1
        WHEN signup_method = 1 THEN 0
        WHEN signup_method = 2 THEN 1
        WHEN signup_method = 3 THEN 0
        WHEN signup_method = 4 THEN NULL
        WHEN signup_method = 5 THEN 2
        ELSE signup_method
      END
    SQL
  end

  def down
    # No-op: the mapping is lossy (we lose pre_signup, lottery_online,
    # invite_only as distinct values).
  end
end
