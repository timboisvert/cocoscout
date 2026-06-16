# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Message document link previews", type: :model do
  let(:org) { create(:organization) }
  let(:production) { create(:production, organization: org) }
  let(:document) { production.documents.create!(title: "Handbook", body: "<div>hi</div>") }

  it "attaches a regard when a manage document URL is in the body" do
    msg = create(:message, organization: org,
      body: %(Please read <a href="https://app.cocoscout.com/manage/productions/#{production.id}/documents/#{document.id}">the handbook</a>.))

    expect(msg.document_regards).to include(document)
  end

  it "attaches a regard when a my-namespace document URL is in the body" do
    msg = create(:message, organization: org,
      body: %(Here it is: https://app.cocoscout.com/my/documents/#{document.id}))

    expect(msg.document_regards).to include(document)
  end

  it "does not attach anything when there is no document link" do
    msg = create(:message, organization: org, body: "Just a normal message, no links.")
    expect(msg.document_regards).to be_empty
  end

  it "does not collide with other documents/:id routes" do
    msg = create(:message, organization: org,
      body: %(See /manage/money/contracts/3/documents/#{document.id} for the contract.))

    expect(msg.document_regards).to be_empty
  end
end
