# frozen_string_literal: true

require "rails_helper"
require "rake"

# The payee payout notice ships its copy from the seed task, not from the app,
# so this is the only place the real wording is exercised. (The spec suite's
# shared fixture in spec/support/database_cleaner.rb is a simplified stand-in.)
RSpec.describe "content_templates:ensure_contract_templates" do
  before do
    Rake::Task.clear
    Rails.application.load_tasks
    ContentTemplate.where(key: "payout_sent_to_payee").delete_all
  end

  after { Rake::Task.clear }

  def run_task
    Rake::Task["content_templates:ensure_contract_templates"].reenable
    silence_stream { Rake::Task["content_templates:ensure_contract_templates"].invoke }
  end

  def silence_stream
    original = $stdout
    $stdout = StringIO.new
    yield
  ensure
    $stdout = original
  end

  it "seeds the payee payout notice on both email and in-app, and never duplicates it" do
    run_task

    template = ContentTemplate.find_by(key: "payout_sent_to_payee")
    expect(template.channel).to eq("both")
    expect(template).to be_active

    run_task
    expect(ContentTemplate.where(key: "payout_sent_to_payee").count).to eq(1)
  end

  it "renders one branch at a time and never names our payout provider" do
    run_task

    base = {
      recipient_name: "Allison", organization_name: "Stars and Garters",
      amount: "$150.00", expected_window: "August 7 – August 11, 2026",
      payments_url: "https://cocoscout.example/my/payments"
    }

    returning = ContentTemplateService.render("payout_sent_to_payee", base.merge(returning_payout: true))[:body]
    first     = ContentTemplateService.render("payout_sent_to_payee", base.merge(first_payout: true))[:body]
    no_bank   = ContentTemplateService.render("payout_sent_to_payee", base.merge(needs_bank: true))[:body]

    expect(returning).to include("on its way to your bank").and include("August 7")
    expect(returning).not_to include("first payment")
    expect(returning).not_to include("set aside")

    expect(first).to include("first payment through CocoScout").and include("our payout provider")
    expect(first).not_to include("set aside")

    expect(no_bank).to include("set aside for you").and include("haven't connected a bank")
    expect(no_bank).not_to include("first payment")

    # The subject must not promise a deposit we can't actually send.
    sending_subject = ContentTemplateService.render("payout_sent_to_payee", base.merge(sending: true))[:subject]
    waiting_subject = ContentTemplateService.render("payout_sent_to_payee", base.merge(needs_bank: true))[:subject]
    expect(sending_subject).to eq("$150.00 is on its way from Stars and Garters")
    expect(waiting_subject).to eq("$150.00 from Stars and Garters is waiting for you")

    # Tim's rule: the payout provider is never named to the payee.
    [ returning, first, no_bank ].each do |body|
      expect(body).not_to match(/stripe/i)
      expect(body).not_to include("{{")  # no unfilled tokens leaking into an email
    end
  end
end
