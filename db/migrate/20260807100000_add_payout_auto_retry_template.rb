# frozen_string_literal: true

# Money that moves without anyone clicking has to leave a trail. When the
# automatic retry pays someone who was parked on a funded run waiting to
# connect a bank, the org's payout-notification managers hear about it.
#
# Migration-owned so it ships with the deploy rather than depending on someone
# remembering a rake task — the job renders this template inside a paying path.
class AddPayoutAutoRetryTemplate < ActiveRecord::Migration[8.1]
  class Template < ActiveRecord::Base
    self.table_name = "content_templates"
  end

  def up
    template = Template.find_or_initialize_by(key: "payout_auto_retry_paid")
    template.assign_attributes(
      name: "Payout Auto-Retry Paid (manager alert)",
      subject: "{{total}} paid automatically on your payout run",
      body: "<p>{{people}} connected a bank account, so we sent the money that was " \
            "waiting for {{people_count}} on your payout run — <strong>{{total}}</strong> in total.</p>" \
            "<p>You didn't need to do anything; the run was already funded.</p>" \
            "<p><a href=\"{{payout_run_url}}\">View the payout run</a></p>",
      category: "payments",
      channel: "message",
      active: true,
      available_variables: %w[organization_name people people_count total payout_run_url]
    )
    template.save!
  end

  def down
    Template.where(key: "payout_auto_retry_paid").delete_all
  end
end
