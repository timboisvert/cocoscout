# frozen_string_literal: true

# Starter wording for a brand-new staff agreement template, prefilled into the
# editor (mirrors ContractTemplateDefaults). It's a scaffold the org edits — the
# staff member agrees to it during onboarding.
module StaffAgreementTemplateDefaults
  DEFAULT_CONTENT = <<~HTML.strip
    <div><strong>Staff Agreement between {{organization_name}} and {{staff_name}}</strong></div><div><br></div><div>This agreement is made on {{current_date}} between {{organization_name}} ("the Organization") and {{staff_name}} ("the Staff Member") for the role of {{title}} in {{department}}, beginning {{start_date}}.</div><div><br></div><div><strong>1. Role &amp; Responsibilities</strong></div><div><br></div><ul><li>The Staff Member will perform the duties of their role professionally and in good faith.</li><li>The Organization will provide the schedule, information, and support needed to do the work.</li><li>Both parties will communicate promptly about scheduling, conflicts, or any issues that arise.</li></ul><div><br></div><div><strong>2. Scheduling &amp; Hours</strong></div><div><br></div><div>The Staff Member will be scheduled for shifts through CocoScout and is expected to confirm availability and report hours worked accurately.</div><div><br></div><div><strong>3. Pay</strong></div><div><br></div><div>The Staff Member will be paid at the rate(s) agreed for their role(s), for the hours worked, according to the Organization's normal pay schedule.</div><div><br></div><div><strong>4. Conduct</strong></div><div><br></div><div>The Staff Member agrees to follow the Organization's policies and to treat colleagues, performers, and patrons with respect.</div><div><br></div><div><strong>5. Acknowledgment</strong></div><div><br></div><div>By agreeing below, the Staff Member acknowledges that they have read, understand, and accept this agreement.</div>
  HTML
end
