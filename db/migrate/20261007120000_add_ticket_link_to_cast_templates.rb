# frozen_string_literal: true

# Cast emails can share where friends buy tickets: {{ticket_link}} joins the
# cast notification templates' variables (Round 9 §3). The copy itself is
# the organization's to change.
class AddTicketLinkToCastTemplates < ActiveRecord::Migration[8.1]
  def up
    ContentTemplate.where(key: %w[cast_notification removed_from_cast_notification]).find_each do |template|
      vars = Array(template.available_variables)
      next if vars.any? { |v| (v.is_a?(Hash) ? v["name"] : v) == "ticket_link" }

      vars << (vars.first.is_a?(Hash) ? { "name" => "ticket_link", "description" => "Where their friends buy tickets (blank when there are none)" } : "ticket_link")
      template.update_columns(available_variables: vars)
    end
  end

  def down; end
end
