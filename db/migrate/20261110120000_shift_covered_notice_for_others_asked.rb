# frozen_string_literal: true

# When a shift someone couldn't make is covered, the other people who were
# asked and hadn't answered are notified that it's gone (Tim, 2026-11-10:
# "this shift has been covered and is no longer available"). A notification
# only: no email. Migration-owned, so production has it on deploy.
class ShiftCoveredNoticeForOthersAsked < ActiveRecord::Migration[8.1]
  class Template < ActiveRecord::Base
    self.table_name = "content_templates"
  end

  KEY = "shift_vacancy_covered_invitee"

  def up
    template = Template.find_or_initialize_by(key: KEY)
    template.assign_attributes(
      name: "Shift covered (others asked)", category: "staffing", channel: "message",
      subject: "The {{role_name}} shift on {{shift_date}} has been covered",
      push_body: "The {{role_name}} shift on {{shift_date}} has been covered",
      body: "<p>Hi {{recipient_name}}, the <strong>{{role_name}}</strong> shift on <strong>{{shift_time}}</strong> that {{organization_name}} asked you about has been covered and is no longer available.</p><p>There's nothing you need to do.</p>",
      available_variables: %w[recipient_name organization_name role_name shift_date shift_time],
      active: true, template_type: "structured"
    )
    template.save!
  end

  def down
    Template.where(key: KEY).delete_all
  end
end
