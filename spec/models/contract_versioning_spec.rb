# frozen_string_literal: true

require "rails_helper"

# Amending an executed contract used to change the deal while the signed
# snapshot stayed frozen — the document both parties signed silently stopped
# describing the arrangement, and the PDF never caught up.
RSpec.describe "Contract versioning", type: :model do
  let(:owner) { create(:user) }
  let(:org) { create(:organization, owner: owner) }
  let(:template) { org.contract_templates.create!(name: "Standard", content: "<p>Agreement for {{contractor_name}}</p>") }
  let(:contract) do
    create(:contract, :active, organization: org, contractor_name: "Quinn James",
                               signing_mode: :esign, contract_template: template)
  end

  def sign_and_execute!
    contract.sign_by_org!(signer_name: "Tim", signed_by: owner, request: nil)
    contract.send_for_signature!
    contract.execute_by_signature!(signer_name: "Quinn", signer_email: "q@example.com",
                                   request: double(remote_ip: "1.2.3.4", user_agent: "rspec"))
  end

  describe "signing" do
    it "cuts v1 and hangs the signatures off it" do
      sign_and_execute!

      version = contract.reload.current_version
      expect(version.version_number).to eq(1)
      expect(version.contract_signatures.map(&:signer_role)).to contain_exactly("organization", "contractor")
      expect(version.executed_at).to be_present
    end

    it "signs exactly the text the version holds, never a second render" do
      contract.sign_by_org!(signer_name: "Tim", signed_by: owner, request: nil)

      version = contract.reload.current_version
      expect(version.organization_signature.content_snapshot).to eq(version.content_snapshot)
    end
  end

  describe "re-signing after an amendment" do
    it "keeps v1's signatures instead of deleting them" do
      sign_and_execute!
      v1 = contract.reload.current_version
      v1_org_signature = v1.organization_signature

      contract.update!(signing_state: :unsent)
      contract.cut_version!(requires_signature: true, created_by: owner, change_summary: "Amended financials")
      contract.reload.sign_by_org!(signer_name: "Tim", signed_by: owner, request: nil)

      # The whole point: v1's signed record survives v2 being signed.
      expect(ContractSignature.exists?(v1_org_signature.id)).to be(true)
      expect(v1.reload.contract_signatures.count).to eq(2)
      expect(contract.reload.current_version.version_number).to eq(2)
      expect(contract.current_version.organization_signature).not_to eq(v1_org_signature)
    end
  end

  describe "an internal correction" do
    it "takes effect at once and carries the previous signatures forward, labelled" do
      sign_and_execute!
      v1 = contract.reload.current_version

      v2 = contract.cut_version!(requires_signature: false, created_by: owner, change_summary: "Fixed a typo")

      expect(v2.executed_at).to be_present
      expect(v2.contract_signatures).to be_empty
      expect(v2.effective_signatures.map(&:id)).to match_array(v1.contract_signatures.map(&:id))
      expect(v2.carried_forward?).to be(true)
    end
  end

  describe "versions before signing" do
    it "refreshes in place rather than stacking up version numbers" do
      contract.cut_version!(requires_signature: true)
      contract.reload.sign_by_org!(signer_name: "Tim", signed_by: owner, request: nil)

      expect(contract.reload.contract_versions.count).to eq(1)
    end
  end

  describe "stale signing links" do
    it "recognises a superseded version's token" do
      sign_and_execute!
      old_token = contract.reload.signing_token
      contract.current_version.update!(signing_token: old_token)
      contract.cut_version!(requires_signature: true)

      found = ContractVersion.find_by(signing_token: old_token)
      expect(found).to be_present
      expect(found.superseded?).to be(true)
    end
  end

  describe "appendixes" do
    it "renders into the document above the signature block" do
      contract.contract_appendixes.create!(title: "Tech Rider", position: 0,
                                           body: "<p>Two monitors, one vocal mic.</p>")

      doc = contract.render_signable_document
      expect(doc).to include("Appendix A — Tech Rider")
      expect(doc).to include("Two monitors, one vocal mic.")
    end

    it "is baked into the snapshot, so editing it later can't rewrite a signed document" do
      appendix = contract.contract_appendixes.create!(title: "Tech Rider", position: 0, body: "<p>Original.</p>")
      sign_and_execute!
      snapshot = contract.reload.current_version.content_snapshot

      appendix.update!(body: "<p>Changed after signing.</p>")

      expect(contract.reload.current_version.content_snapshot).to eq(snapshot)
      expect(contract.current_version.content_snapshot).to include("Original.")
      expect(contract.current_version.content_snapshot).not_to include("Changed after signing.")
    end

    it "letters them in order" do
      contract.contract_appendixes.create!(title: "Rider", position: 0, body: "<p>a</p>")
      second = contract.contract_appendixes.create!(title: "Hospitality", position: 1, body: "<p>b</p>")

      expect(second.reload.heading).to eq("Appendix B — Hospitality")
    end
  end

  describe "PDFs" do
    it "renders only that version's signatures, not every one ever collected" do
      sign_and_execute!
      v1 = contract.reload.current_version
      v2 = contract.cut_version!(requires_signature: false)

      expect(ContractPdf.new(v1).render[0, 4]).to eq("%PDF")
      # v2 carries v1's two forward — and still only two.
      expect(v2.effective_signatures.size).to eq(2)
    end

    it "generates a separate document per version" do
      sign_and_execute!
      v1 = contract.reload.current_version
      GenerateContractPdfJob.perform_now(contract.id, v1.id)

      v2 = contract.cut_version!(requires_signature: false)
      GenerateContractPdfJob.perform_now(contract.id, v2.id)

      expect(v1.reload.pdf_document).to be_present
      expect(v2.reload.pdf_document).to be_present
      expect(v1.pdf_document.id).not_to eq(v2.pdf_document.id)
    end

    it "keeps serving the last executed version's PDF while a newer one awaits signature" do
      sign_and_execute!
      v1 = contract.reload.current_version
      GenerateContractPdfJob.perform_now(contract.id, v1.id)
      contract.cut_version!(requires_signature: true) # awaiting signature, no PDF

      expect(contract.reload.signed_pdf_document).to eq(v1.reload.pdf_document)
    end
  end
end
