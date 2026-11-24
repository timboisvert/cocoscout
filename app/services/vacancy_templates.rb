# frozen_string_literal: true

# The words of the notice a production team gets when one person gives up
# several acts in a show at once (VacancyNotificationService
# .notify_vacancies_created; Tim, 2026-11-24): one notice that names every
# act, in place of one "vacancy_created" notice per act. A seeded
# ContentTemplate, sent the way "vacancy_created" is: a notification, and an
# email only to someone with no account.
class VacancyTemplates
  SEVERAL = "vacancy_created_several"

  TEMPLATES = [
    { key: SEVERAL, name: "Vacancies Created: several acts at once (Producer Notification)",
      description: "Sent to producers when a cast member indicates they can't make several of their acts in one show",
      subject: "{{person_name}} can't make {{how_many}} on {{show_date}}",
      body: %(<p>Hi, {{recipient_name}}</p><p><strong>{{person_name}}</strong> can't make {{how_many}} in <strong>{{production_name}}</strong> on <strong>{{show_date}}</strong>: {{names}}.</p><p>A vacancy has been created for each one, and you can now invite replacements.</p><p><a href="{{show_url}}">Open the show's cast</a></p>),
      variables: [
        { "name" => "recipient_name", "description" => "The first name of whoever gets the notice" },
        { "name" => "person_name", "description" => "Who can't make it" },
        { "name" => "how_many", "description" => "How many, e.g. 2 acts" },
        { "name" => "names", "description" => "Each one by name, e.g. Act 2 · Fan Dance and Act 9 · Finale" },
        { "name" => "production_name", "description" => "The production" },
        { "name" => "show_date", "description" => "The show's date and time, e.g. December 12 at 8:00 PM" },
        { "name" => "show_url", "description" => "The show's cast page" }
      ] }
  ].freeze

  def self.ensure!(keys: nil, overwrite: false)
    TEMPLATES.each do |spec|
      next if keys && !keys.include?(spec[:key])

      template = ContentTemplate.find_or_initialize_by(key: spec[:key])
      next if template.persisted? && !overwrite

      template.assign_attributes(name: spec[:name], description: spec[:description], category: "shows", channel: "both",
                                 template_type: "structured", active: true, subject: spec[:subject], body: spec[:body],
                                 available_variables: spec[:variables])
      template.save!
    end
  end
end
