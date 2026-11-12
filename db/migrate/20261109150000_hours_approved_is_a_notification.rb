# frozen_string_literal: true

# "Hours approved" was an email as well as a notification (Tim, 2026-11-09:
# "shouldn't that just be a notification and not an email?"). The template
# stops emailing; StaffHoursApprovedNotice no longer names a mailer.
class HoursApprovedIsANotification < ActiveRecord::Migration[8.1]
  class Template < ActiveRecord::Base
    self.table_name = "content_templates"
  end

  def up
    Template.where(key: "staff_hours_approved").update_all(channel: "message")
  end

  def down
    Template.where(key: "staff_hours_approved").update_all(channel: "both")
  end
end
