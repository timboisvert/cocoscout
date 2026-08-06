# frozen_string_literal: true

# Staffing gets its own notification list, mirroring the contracts one: the org
# picks which managers hear about staffing events. First event wired up: a staff
# member marking a shift "can't make it" — until now that only surfaced if a
# manager happened to look at the scheduling page.
#
# The template is owned by this migration (not the seed rake task) so production
# gets it on deploy without a manual step.
class AddStaffingNotifications < ActiveRecord::Migration[8.1]
  class Template < ActiveRecord::Base
    self.table_name = "content_templates"
  end

  def up
    add_column :organizations, :staffing_notification_user_ids, :jsonb, default: [], null: false

    template = Template.find_or_initialize_by(key: "shift_declined_manager")
    template.assign_attributes(
      name: "Shift Declined (manager alert)",
      subject: "{{person_name}} can't make a shift",
      body: "<p>{{person_name}} can't make their <strong>{{role_name}}</strong> shift " \
            "on <strong>{{shift_time}}</strong>.</p>" \
            "{{#decline_reason}}<p>Their note: “{{decline_reason}}”</p>{{/decline_reason}}" \
            "<p><a href=\"{{scheduling_url}}\">View that day in Staffing Scheduling</a></p>",
      category: "staffing",
      channel: "message",
      active: true,
      available_variables: %w[person_name role_name shift_time decline_reason organization_name scheduling_url]
    )
    template.save!
  end

  def down
    remove_column :organizations, :staffing_notification_user_ids
    Template.where(key: "shift_declined_manager").delete_all
  end
end
