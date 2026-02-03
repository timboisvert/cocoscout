class CreateVacancyProducerNotificationTemplates < ActiveRecord::Migration[8.1]
  def up
    # Vacancy created notification - for producers when someone can't make a show
    ContentTemplate.find_or_create_by!(key: "vacancy_created") do |t|
      t.name = "Vacancy Created (Producer Notification)"
      t.category = "shows"
      t.channel = "both"
      t.template_type = "structured"
      t.description = "Sent to producers when a cast member indicates they can't make a show"
      t.subject = "{{person_name}} can't make {{show_date}}"
      t.body = <<~HTML
        <p>Hi {{recipient_name}},</p>
        <p><strong>{{person_name}}</strong> has indicated they can't make it to the show on <strong>{{show_date}}</strong> for the role of <strong>{{role_name}}</strong>.</p>
        <p>A vacancy has been created and you can now invite replacements.</p>
        <p><a href="{{vacancy_url}}">View Vacancy &amp; Invite Replacements →</a></p>
      HTML
    end

    # Vacancy filled notification - for producers when a vacancy is filled
    ContentTemplate.find_or_create_by!(key: "vacancy_filled") do |t|
      t.name = "Vacancy Filled (Producer Notification)"
      t.category = "shows"
      t.channel = "both"
      t.template_type = "structured"
      t.description = "Sent to producers when a vacancy is filled"
      t.subject = "Vacancy filled: {{role_name}} for {{show_date}}"
      t.body = <<~HTML
        <p>Hi {{recipient_name}},</p>
        <p>Great news! The vacancy for <strong>{{role_name}}</strong> on <strong>{{show_date}}</strong> has been filled by <strong>{{filled_by_name}}</strong>.</p>
        <p><a href="{{show_url}}">View Show Casting →</a></p>
      HTML
    end

    # Vacancy reclaimed notification - for producers when person comes back
    ContentTemplate.find_or_create_by!(key: "vacancy_reclaimed") do |t|
      t.name = "Vacancy Reclaimed (Producer Notification)"
      t.category = "shows"
      t.channel = "both"
      t.template_type = "structured"
      t.description = "Sent to producers when someone reclaims their spot after saying they couldn't make it"
      t.subject = "{{person_name}} is back for {{show_date}}"
      t.body = <<~HTML
        <p>Hi {{recipient_name}},</p>
        <p><strong>{{person_name}}</strong> has indicated they can now make it to the show on <strong>{{show_date}}</strong>.</p>
        <p>The vacancy has been cancelled and they are back in their role of <strong>{{role_name}}</strong>.</p>
        <p><a href="{{show_url}}">View Show Casting →</a></p>
      HTML
    end
  end

  def down
    ContentTemplate.where(key: %w[vacancy_created vacancy_filled vacancy_reclaimed]).destroy_all
  end
end
