# frozen_string_literal: true

require "rails_helper"

RSpec.describe SignIn::Code do
  include ActiveJob::TestHelper

  it "emails a code that then redeems" do
    expect {
      expect(described_class.deliver(email: "maya@example.com", purpose: "sign_in")).to eq(:sent)
    }.to have_enqueued_mail(AuthMailer, :sign_in_code)

    perform_enqueued_jobs
    mail = ActionMailer::Base.deliveries.last
    expect(mail.to).to eq([ "maya@example.com" ])
    code = mail.subject[/\d{6}/]
    expect(code).to be_present
    expect(mail.body.encoded).to include(code).and include("10 minutes")

    expect(described_class.redeem(email: "maya@example.com", purpose: "sign_in", code: code).first).to eq(:ok)
  end

  it "never puts the code in plain text in the mail job's arguments" do
    described_class.deliver(email: "maya@example.com", purpose: "sign_in")
    job = ActiveJob::Base.queue_adapter.enqueued_jobs.last
    sealed = job[:args][3]["args"][1]

    perform_enqueued_jobs
    code = ActionMailer::Base.deliveries.last.subject[/\d{6}/]
    expect(job[:args].to_s).not_to include(code)
    expect(described_class.unseal(sealed)).to eq(code)
    expect(described_class.unseal(code)).to be_nil
  end

  it "sends nothing when a code went out moments ago" do
    described_class.deliver(email: "maya@example.com", purpose: "sign_in")

    expect {
      expect(described_class.deliver(email: "maya@example.com", purpose: "sign_in")).to eq(:too_soon)
    }.not_to have_enqueued_mail(AuthMailer, :sign_in_code)
  end
end
