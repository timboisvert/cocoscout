# frozen_string_literal: true

# Starter wording for a brand-new contract template, prefilled into the editor
# (mirrors AgreementTemplateDefaults). It's a scaffold the org edits — the deal's
# concrete dates/financials/services are appended automatically as a "Deal Terms"
# schedule at signing time, so this is just the surrounding legal language.
module ContractTemplateDefaults
  DEFAULT_CONTENT = <<~HTML.strip
    <div><strong>Contract Agreement between {{organization_name}} and {{contractor_name}}</strong></div><div><br></div><div>This agreement is made on {{current_date}} between {{organization_name}} ("the Organization") and {{contractor_name}} ("the Contractor") in connection with {{production_name}}.</div><div><br></div><div><strong>1. Term</strong></div><div><br></div><div>This agreement covers the period from {{contract_start_date}} through {{contract_end_date}}, and the bookings, financial terms, and services detailed in the Deal Terms below.</div><div><br></div><div><strong>2. Responsibilities</strong></div><div><br></div><ul><li>The Contractor will perform the engagement described in the Deal Terms in a professional manner.</li><li>The Organization will provide the space, dates, and services described in the Deal Terms.</li><li>Both parties will communicate promptly about any conflicts, changes, or issues.</li></ul><div><br></div><div><strong>3. Payment</strong></div><div><br></div><div>Payment will be made according to the financial terms in the Deal Terms below.</div><div><br></div><div><strong>4. Acknowledgment</strong></div><div><br></div><div>By signing below, the Contractor acknowledges that they have read, understand, and agree to this agreement and the attached Deal Terms as a binding contract.</div>
  HTML
end
