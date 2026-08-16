class RemoveExcludedRoleIdsFromPayoutRules < ActiveRecord::Migration[8.1]
  # Payout schemes could keep a role out of payouts ("excluded_role_ids" inside
  # the rules JSON). Across the whole app it was configured on exactly one
  # scheme and never actually kept a single person out of a calculated payout,
  # so the feature is gone. Strip the dead key out of the stored rules.
  def up
    execute(<<~SQL.squish)
      UPDATE payout_schemes
         SET rules = rules - 'excluded_role_ids'
       WHERE rules IS NOT NULL
         AND jsonb_exists(rules, 'excluded_role_ids')
    SQL

    execute(<<~SQL.squish)
      UPDATE show_payouts
         SET override_rules = override_rules - 'excluded_role_ids'
       WHERE override_rules IS NOT NULL
         AND jsonb_exists(override_rules, 'excluded_role_ids')
    SQL
  end

  def down
    # Nothing reads the key any more, and the role lists themselves are gone —
    # there is nothing to put back.
  end
end
