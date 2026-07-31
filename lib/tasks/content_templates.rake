# frozen_string_literal: true

namespace :content_templates do
  desc "Apply the Stripe-bank payment updates to content templates (idempotent, env-aware)"
  task apply_payment_updates: :environment do
    PaymentTemplateUpdater.apply!.each { |line| puts line }
  end

  desc "Ensure contract-related content templates exist (idempotent). Run at deploy."
  task ensure_contract_templates: :environment do
    # Sent to an existing CocoScout member when they're added to a contract
    # (non-members get the person_invitation instead). Message channel: it posts
    # as an in-app notification and rolls into their unread-email digest.
    template = ContentTemplate.find_or_initialize_by(key: "contract_person_added")
    if template.new_record?
      template.update!(
        name: "Added to a Contract",
        subject: "{{organization_name}} added you to a contract",
        body: "<p>{{organization_name}} has set you up on a contract in CocoScout. " \
              "<a href=\"{{contracts_url}}\">View your contracts</a>.</p>",
        category: "invitations",
        channel: "message",
        active: true
      )
      puts "Created content template: contract_person_added"
    else
      puts "content template contract_person_added already exists — left as is"
    end

    # Sent to the org's chosen managers when a contract is signed by the
    # counterparty. Message-only (no email); renders as an automated notification.
    signed = ContentTemplate.find_or_initialize_by(key: "contract_signed_manager")
    if signed.new_record?
      signed.update!(
        name: "Contract Signed (manager alert)",
        subject: "{{contractor_name}} signed a contract",
        body: "<p>{{contractor_name}} signed the contract for {{production_name}}. " \
              "<a href=\"{{contract_url}}\">View the contract</a>.</p>",
        category: "notifications",
        channel: "message",
        active: true
      )
      puts "Created content template: contract_signed_manager"
    else
      puts "content template contract_signed_manager already exists — left as is"
    end
  end
end
