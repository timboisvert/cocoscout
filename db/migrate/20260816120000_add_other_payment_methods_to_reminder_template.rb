# frozen_string_literal: true

# The payment reminder now tells the payer the other ways their contract lets
# them settle up (check, Zelle, …) — only what the contract allows, nothing when
# it's online-only. Adds the {{other_payment_methods}} variable to the seeded
# template. Idempotent, and it leaves a template someone has already rewritten
# by hand alone rather than clobbering their copy.
class AddOtherPaymentMethodsToReminderTemplate < ActiveRecord::Migration[8.1]
  KEY = "contract_payment_reminder"
  ANCHOR = "<p>Or open this link to pay: {{pay_url}}</p>"
  ADDITION = <<~HTML.strip
    <p>Or open this link to pay: {{pay_url}}</p>
    {{#other_payment_methods}}<p>You're also welcome to pay by {{other_payment_methods}} — reach out to {{organization_name}} to arrange it.</p>{{/other_payment_methods}}
  HTML
  VARIABLE = { "name" => "other_payment_methods",
               "description" => "The other ways this contract lets them pay (e.g. \"Zelle or check\"); blank when online-only" }.freeze

  def up
    template = ContentTemplate.find_by(key: KEY)
    return unless template

    body = template.body.to_s
    body = body.sub(ANCHOR, ADDITION) if body.include?(ANCHOR) && !body.include?("{{other_payment_methods}}")
    variables = Array(template.available_variables)
    variables << VARIABLE unless variables.any? { |v| v["name"] == VARIABLE["name"] }
    template.update!(body: body, available_variables: variables)
  end

  def down
    template = ContentTemplate.find_by(key: KEY)
    return unless template

    template.update!(
      body: template.body.to_s.sub(ADDITION, ANCHOR),
      available_variables: Array(template.available_variables).reject { |v| v["name"] == VARIABLE["name"] }
    )
  end
end
