# frozen_string_literal: true

require "rails_helper"

# The receipt. Most counterparties have no CocoScout account, so the email —
# with the countersigned PDF attached — is the copy they actually keep.
RSpec.describe ContractCountersignedNotificationJob, type: :job do
  let(:owner) { create(:user) }
  let!(:org) { create(:organization, owner: owner) }
  let(:signer) { create(:person, name: "Quinn James", email: "quinn@example.com", user: create(:user)) }
  let(:contractor) { create(:contractor, organization: org, person: signer) }
  let!(:template) { org.contract_templates.create!(name: "Standard", content: "<p>For {{contractor_name}}</p>") }
  let!(:contract) do
    create(:contract, :active, organization: org, contractor: contractor, contractor_name: "Quinn James",
                               signing_mode: :esign, contract_template: template)
  end

  def execute!
    contract.sign_by_org!(signer_name: "Tim", signed_by: owner, request: nil)
    contract.send_for_signature!
    contract.execute_by_signature!(signer_name: "Quinn", signer_email: "quinn@example.com",
                                   request: double(remote_ip: "1.2.3.4", user_agent: "rspec"))
    contract.reload
  end

  it "emails the counterparty with the signed PDF attached" do
    execute!
    version = contract.current_version
    GenerateContractPdfJob.perform_now(contract.id, version.id)

    expect { described_class.perform_now(contract.id, version.id) }
      .to change { ActionMailer::Base.deliveries.size }.by(1)

    mail = ActionMailer::Base.deliveries.last
    expect(mail.to).to eq([ "quinn@example.com" ])
    expect(mail.subject).to include("Signed")
    # The mailer layout carries its own inline logo, so look for the PDF itself.
    pdfs = mail.attachments.select { |a| a.content_type.to_s.include?("application/pdf") }
    expect(pdfs.size).to eq(1)
    expect(pdfs.first.filename).to include("contract")
  end

  it "also posts a CocoScout message pointing at their contracts page" do
    execute!
    version = contract.current_version
    GenerateContractPdfJob.perform_now(contract.id, version.id)

    expect { described_class.perform_now(contract.id, version.id) }.to change(Message, :count).by(1)
    expect(Message.order(:created_at).last.body.to_s).to include("contracts")
  end

  it "is triggered by the PDF job only when the signing path asked for it" do
    execute!
    version = contract.current_version

    expect {
      GenerateContractPdfJob.perform_now(contract.id, version.id, notify_signer: true)
    }.to change {
      ActiveJob::Base.queue_adapter.enqueued_jobs.count { |j| j["job_class"] == "ContractCountersignedNotificationJob" }
    }.by(1)
  end

  it "stays quiet when an old contract's PDF is backfilled" do
    execute!
    version = contract.current_version

    expect {
      GenerateContractPdfJob.perform_now(contract.id, version.id)
    }.not_to change {
      ActiveJob::Base.queue_adapter.enqueued_jobs.count { |j| j["job_class"] == "ContractCountersignedNotificationJob" }
    }
  end

  it "does nothing for a contract that isn't executed" do
    contract.sign_by_org!(signer_name: "Tim", signed_by: owner, request: nil)

    expect { described_class.perform_now(contract.id) }.not_to change { ActionMailer::Base.deliveries.size }
  end
end
