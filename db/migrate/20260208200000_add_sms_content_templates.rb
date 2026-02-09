class AddSmsContentTemplates < ActiveRecord::Migration[8.1]
  def up
    ContentTemplate.find_or_create_by!(key: "sms_show_cancellation") do |t|
      t.name = "SMS: Show Cancellation"
      t.description = "SMS sent when a show is cancelled"
      t.category = "sms"
      t.channel = "email"
      t.template_type = "structured"
      t.subject = "Show Cancelled"
      t.body = "CocoScout: {{production_name}} - {{show_name}} on {{show_date}} cancelled. {{dashboard_url}} Reply STOP to opt out."
      t.available_variables = [
        { "name" => "production_name", "description" => "Name of the production" },
        { "name" => "show_name", "description" => "Name of the show" },
        { "name" => "show_date", "description" => "Date of the show" },
        { "name" => "dashboard_url", "description" => "Link to the dashboard" }
      ]
      t.active = true
    end

    ContentTemplate.find_or_create_by!(key: "sms_vacancy_created") do |t|
      t.name = "SMS: Vacancy Created"
      t.description = "SMS sent when a vacancy is created and cast members are notified"
      t.category = "sms"
      t.channel = "email"
      t.template_type = "structured"
      t.subject = "Vacancy Created"
      t.body = "CocoScout: Vacancy for {{role_name}} in {{production_name}} on {{show_date}}. {{link}} Reply STOP to opt out."
      t.available_variables = [
        { "name" => "role_name", "description" => "Name of the role" },
        { "name" => "production_name", "description" => "Name of the production" },
        { "name" => "show_date", "description" => "Date of the show" },
        { "name" => "link", "description" => "Link to claim the vacancy or dashboard" }
      ]
      t.active = true
    end

    ContentTemplate.find_or_create_by!(key: "sms_vacancy_filled") do |t|
      t.name = "SMS: Vacancy Filled"
      t.description = "SMS sent when a vacancy has been filled"
      t.category = "sms"
      t.channel = "email"
      t.template_type = "structured"
      t.subject = "Vacancy Filled"
      t.body = "CocoScout: Vacancy filled - {{role_name}} for {{production_name}} on {{show_date}}. Reply STOP to opt out."
      t.available_variables = [
        { "name" => "role_name", "description" => "Name of the role" },
        { "name" => "production_name", "description" => "Name of the production" },
        { "name" => "show_date", "description" => "Date of the show" }
      ]
      t.active = true
    end
  end

  def down
    ContentTemplate.where(key: %w[sms_show_cancellation sms_vacancy_created sms_vacancy_filled]).destroy_all
  end
end
