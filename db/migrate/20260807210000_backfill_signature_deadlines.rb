# frozen_string_literal: true

# Contracts already out for signature when deadlines shipped have no due date,
# and the reminder job reads "no deadline" as "past every threshold" — so on the
# first morning after deploy each one would have received a final-warning email
# with a blank date and "expires in 0 days".
#
# Give them a real deadline measured from now, and mark their reminders as
# already sent so nobody gets a retroactive burst for a contract that's been
# sitting quietly. From here they behave normally: they expire on the new date.
class BackfillSignatureDeadlines < ActiveRecord::Migration[8.1]
  class Version < ActiveRecord::Base
    self.table_name = "contract_versions"
  end

  def up
    Version.where(executed_at: nil, expired_at: nil, signature_due_at: nil)
           .where.not(sent_for_signature_at: nil)
           .find_each do |version|
      days = ActiveRecord::Base.connection.select_value(
        "SELECT o.signature_expiry_days FROM contracts c " \
        "JOIN organizations o ON o.id = c.organization_id WHERE c.id = #{version.contract_id.to_i}"
      ).to_i
      days = 14 unless [ 7, 14, 30 ].include?(days)

      version.update_columns(
        signature_due_at: days.days.from_now.end_of_day,
        # Past every threshold already; skip straight to the deadline.
        nudge_count: 3,
        updated_at: Time.current
      )
    end
  end

  def down
    # Nothing to undo — the columns themselves are dropped by their own migration.
  end
end
