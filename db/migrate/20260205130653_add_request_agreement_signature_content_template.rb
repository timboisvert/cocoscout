class AddRequestAgreementSignatureContentTemplate < ActiveRecord::Migration[8.1]
  def up
    ContentTemplate.create!(
      key: "request_agreement_signature",
      name: "Request Agreement Signature",
      subject: "Please Sign the {{production_name}} Agreement",
      body: <<~BODY,
        Hi {{recipient_name}},

        This is a friendly reminder to sign the performer agreement for **{{production_name}}**.

        Signing the agreement is required before you can be assigned to shows.

        **[Sign the Agreement]({{agreement_url}})**

        If you have any questions about the agreement, please don't hesitate to reach out.

        Thanks!
      BODY
      category: "casting",
      channel: "message",
      template_type: "structured",
      active: true,
      available_variables: [
        { "name" => "recipient_name", "description" => "Recipient's name" },
        { "name" => "production_name", "description" => "Name of the production" },
        { "name" => "agreement_url", "description" => "URL to sign the agreement" }
      ]
    )
  end

  def down
    ContentTemplate.find_by(key: "request_agreement_signature")&.destroy
  end
end
