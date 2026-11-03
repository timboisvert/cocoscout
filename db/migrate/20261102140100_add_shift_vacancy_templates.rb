# frozen_string_literal: true

# The notices around a shift vacancy (Tim, 2026-11-02: the performer flow,
# for staff). The manager alert that already existed now goes by email too
# and leads with the page where they find cover; three new ones: the
# invitation to cover a shift, it's covered, they can make it after all.
# Migration-owned, like the alert, so production has them on deploy.
class AddShiftVacancyTemplates < ActiveRecord::Migration[8.1]
  class Template < ActiveRecord::Base
    self.table_name = "content_templates"
  end

  TEMPLATES = [
    { key: "shift_declined_manager", name: "Shift can't make it (manager alert)",
      subject: "{{person_name}} can't make a shift",
      body: "<p>{{person_name}} can't make their <strong>{{role_name}}</strong> shift " \
            "on <strong>{{shift_time}}</strong>.</p>" \
            "{{#decline_reason}}<p>Their note: “{{decline_reason}}”</p>{{/decline_reason}}" \
            "{{#vacancy_url}}<p><a href=\"{{vacancy_url}}\">Find someone to cover it</a></p>{{/vacancy_url}}" \
            "<p><a href=\"{{scheduling_url}}\">View that day in Staffing Scheduling</a></p>",
      category: "staffing", channel: "both",
      available_variables: %w[person_name role_name shift_time decline_reason organization_name vacancy_url scheduling_url] },
    { key: "shift_vacancy_invitation", name: "Shift cover invitation",
      subject: "Can you cover a {{role_name}} shift on {{shift_date}}?",
      body: "<p>Hi {{recipient_name}},</p>" \
            "<p>{{organization_name}} needs someone on <strong>{{role_name}}</strong>: {{shift_info}}" \
            "{{#location_name}} at {{location_name}}{{/location_name}}.</p>" \
            "{{#shows_list}}<p>That night: {{shows_list}}</p>{{/shows_list}}" \
            "<p><a href=\"{{claim_url}}\" style=\"display:inline-block;background:#ec4899;color:#fff;padding:10px 18px;border-radius:4px;text-decoration:none;font-weight:600\">Claim this shift</a></p>" \
            "<p>First to claim gets it. If you can't, there's no need to reply.</p>",
      category: "staffing", channel: "both",
      available_variables: %w[recipient_name organization_name role_name shift_date shift_time shift_info location_name shows_list claim_url] },
    { key: "shift_vacancy_filled", name: "Shift covered",
      subject: "{{filled_by_name}} is covering the {{role_name}} shift on {{shift_date}}",
      body: "<p>{{filled_by_name}} is covering the <strong>{{role_name}}</strong> shift on <strong>{{shift_time}}</strong> " \
            "that {{person_name}} couldn't make.</p>" \
            "<p><a href=\"{{link_url}}\">{{link_text}}</a></p>",
      category: "staffing", channel: "both",
      available_variables: %w[person_name filled_by_name role_name shift_date shift_time organization_name link_url link_text] },
    { key: "shift_vacancy_reclaimed", name: "Shift can make it after all",
      subject: "{{person_name}} can make their {{role_name}} shift after all",
      body: "<p>{{person_name}} is back on their <strong>{{role_name}}</strong> shift on <strong>{{shift_time}}</strong>.</p>" \
            "<p><a href=\"{{vacancy_url}}\">See the shift</a></p>",
      category: "staffing", channel: "both",
      available_variables: %w[person_name role_name shift_date shift_time organization_name vacancy_url] }
  ].freeze

  def up
    TEMPLATES.each do |attrs|
      template = Template.find_or_initialize_by(key: attrs[:key])
      template.assign_attributes(attrs.merge(active: true))
      template.save!
    end
  end

  def down
    Template.where(key: %w[shift_vacancy_invitation shift_vacancy_filled shift_vacancy_reclaimed]).delete_all
    Template.where(key: "shift_declined_manager").update_all(channel: "message")
  end
end
