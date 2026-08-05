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

    # Emailed to the org's chosen managers (Money settings → Notifications)
    # when a payout run is submitted: names + amounts, expected deposit window,
    # and a link to the run.
    payout_submitted = ContentTemplate.find_or_initialize_by(key: "payout_run_submitted")
    if payout_submitted.new_record?
      payout_submitted.update!(
        name: "Payout Run Submitted (manager alert)",
        subject: "Payout run submitted — {{total}} to {{people_count}}",
        body: "<p>Hi {{recipient_name}},</p>" \
              "<p>A {{run_kind}} payout run for {{organization_name}} was just submitted: " \
              "<strong>{{total}}</strong> to {{people_count}}.</p>" \
              "{{payee_lines}}" \
              "<p>Deposits are expected to land <strong>{{expected_window}}</strong> " \
              "(people who haven't connected a bank yet are paid from this run once they do).</p>" \
              "<p><a href=\"{{payout_run_url}}\">View the payout run</a></p>",
        category: "payments",
        channel: "email",
        active: true
      )
      puts "Created content template: payout_run_submitted"
    else
      puts "content template payout_run_submitted already exists — left as is"
    end

    # NOTE: the payee payout notices (payout_sent_to_payee,
    # payout_sent_to_payee_first_payment, payout_sent_to_payee_no_bank) are
    # owned by db/migrate/20260805100000_split_payout_payee_templates_and_recategorize.rb
    # so they ship with the deploy instead of a manual step — the payout job
    # raises when its template is missing and it runs inside the paying path.

    # Sent to the org's chosen managers when a contract is signed by the
    # counterparty. Message-only (no email); renders as an automated notification.
    signed = ContentTemplate.find_or_initialize_by(key: "contract_signed_manager")
    if signed.new_record?
      signed.update!(
        name: "Contract Signed (manager alert)",
        subject: "{{contractor_name}} signed a contract",
        body: "<p>{{contractor_name}} signed the contract for {{production_name}}. " \
              "<a href=\"{{contract_url}}\">View the contract</a>.</p>",
        category: "contracts",
        channel: "message",
        active: true
      )
      puts "Created content template: contract_signed_manager"
    else
      puts "content template contract_signed_manager already exists — left as is"
    end
  end
end
