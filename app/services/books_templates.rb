# frozen_string_literal: true

# The words of the Books notices added on 2026-11-09 (Tim: "Yes, all of
# it"): an invoice paid on its page, and the three pieces of background
# work whose only notice was the one for when they finished. Each is a
# seeded ContentTemplate (the PlatformTemplates pattern), and each is a
# notification only: the Notifications list and a push, never an email. The
# body is kept for the template's editor and says the same. The older Books
# notices (bank_statement_ready, bank_rules_applied, books_download_ready)
# were seeded by their own migrations.
class BooksTemplates
  HELLO = "<p>Hi {{recipient_name}},</p>"
  WHO = [ { "name" => "recipient_name", "description" => "Who the notice is to" },
          { "name" => "organization_name", "description" => "The organization" } ].freeze

  TEMPLATES = [
    # To whoever made the invoice: a notification (the list and a push), no
    # email (Tim, 2026-11-09: notices are notifications wherever they can be).
    { key: "invoice_paid_online", name: "Invoice paid on its page", channel: "message",
      subject: "{{payer_name}} paid {{amount}} on invoice {{invoice_number}}",
      body: %(#{HELLO}<p>{{payer_name}} paid <strong>{{amount}}</strong> on invoice {{invoice_number}} from {{organization_name}}, on the invoice's page.{{#still_owed}} {{still_owed}} is still owed on it.{{/still_owed}}</p><p>The money is in your CocoScout balance, less the card or bank fee.</p><p><a href="{{invoice_url}}">Open the invoice</a></p>),
      variables: WHO + [ { "name" => "payer_name", "description" => "Who the invoice is to" },
                         { "name" => "amount", "description" => "What they just paid, e.g. $1,200.00" },
                         { "name" => "invoice_number", "description" => "e.g. SG-0014" },
                         { "name" => "still_owed", "description" => "What is left to pay, blank when it is paid in full" },
                         { "name" => "invoice_url", "description" => "The invoice in Money" } ] },
    { key: "bank_statement_failed", name: "Bank statement matching didn't finish", channel: "message",
      subject: "The matching for {{statement}} didn't finish",
      body: %(#{HELLO}<p>The bank statement you brought in for {{organization_name}} ({{statement}}) couldn't be matched to the books all the way through. Its lines are on the Bank page to deal with by hand. To try the matching again, remove the statement and bring it in once more.</p><p><a href="{{bank_url}}">Open the Bank page</a></p>),
      variables: WHO + [ { "name" => "statement", "description" => "The statement's name" },
                         { "name" => "bank_url", "description" => "The Bank page" } ] },
    { key: "bank_rules_failed", name: "Bank rules stopped part way", channel: "message",
      subject: "Your bank rules stopped part way: {{to_deal_with}} lines still waiting",
      body: %(#{HELLO}<p>Running {{organization_name}}'s bank rules over the lines waiting stopped before it finished. The lines it had dealt with stay dealt with, and {{to_deal_with}} are still waiting. Run the rules again from the Rules page.</p><p><a href="{{rules_url}}">Open Rules</a></p>),
      variables: WHO + [ { "name" => "to_deal_with", "description" => "How many lines are still waiting" },
                         { "name" => "rules_url", "description" => "The bank rules page" } ] },
    { key: "books_download_failed", name: "Books download couldn't be made", channel: "message",
      subject: "{{download}} couldn't be put together",
      body: %(#{HELLO}<p>{{download}} for {{organization_name}} couldn't be put together, so there is nothing to download. Ask for it again from Statements.</p><p><a href="{{statements_url}}">Open Statements</a></p>),
      variables: WHO + [ { "name" => "download", "description" => "What was asked for" },
                         { "name" => "statements_url", "description" => "The Statements page" } ] }
  ].freeze

  def self.ensure!(keys: nil, overwrite: false)
    TEMPLATES.each do |spec|
      next if keys && !keys.include?(spec[:key])

      template = ContentTemplate.find_or_initialize_by(key: spec[:key])
      next if template.persisted? && !overwrite

      template.assign_attributes(name: spec[:name], category: "books", channel: spec[:channel], template_type: "structured",
                                 active: true, subject: spec[:subject], body: spec[:body], available_variables: spec[:variables])
      template.save!
    end
  end
end
