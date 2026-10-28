# frozen_string_literal: true

# A refund can carry a message to the buyer, put in their refund email
# (the ticket_order_refunded template's {{refund_message}}), apart from the
# reason, which stays the manager's own note.
class AddBuyerMessageToTicketRefunds < ActiveRecord::Migration[8.1]
  OLD_BODY = %(<p>Hi {{first_name}},</p><p>{{organization_name}} refunded <strong>{{refund_amount}}</strong> for {{ticket_count}} to <strong>{{show_title}}</strong> on {{show_date}}. It goes back to the card you paid with and usually shows up within 5 to 10 business days.</p><p style="color:#6b7280;font-size:12px">Order {{order_code}} · <a href="{{order_url}}">View your order</a></p>)
  BLOCK = %({{#refund_message}}<p>{{refund_message}}</p>{{/refund_message}})

  def up
    add_column :ticket_refunds, :buyer_message, :text

    template = ContentTemplate.find_by(key: "ticket_order_refunded")
    return TicketingTemplates.ensure!(keys: %w[ticket_order_refunded]) unless template
    return if template.body.include?("{{refund_message}}")

    # Unedited: today's words. Edited by a superadmin: the message goes in
    # just above the order line (or at the end), the rest left as they wrote it.
    if template.body == OLD_BODY
      TicketingTemplates.ensure!(keys: %w[ticket_order_refunded], overwrite: true)
    else
      marker = %(<p style="color:#6b7280;font-size:12px">Order)
      body = template.body.include?(marker) ? template.body.sub(marker, BLOCK + marker) : template.body + BLOCK
      template.update!(body: body, available_variables: Array(template.available_variables) +
                         [ { "name" => "refund_message", "description" => "The manager's message to the buyer, if any" } ])
    end
  end

  def down
    remove_column :ticket_refunds, :buyer_message
  end
end
