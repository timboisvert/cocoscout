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

namespace :content_templates do
  # The wording an act-based production needs in its cast notifications
  # ("your act" instead of "your role"). Idempotent: run at deploy, any number
  # of times.
  #
  #   * ensures cast_notification / removed_from_cast_notification exist
  #   * registers the casting_unit / casting_units (and role_name / role_names)
  #     variables on both templates so the editor documents them
  #   * rewrites the BODY only when it still equals the original seeded default
  #     (whitespace-insensitive) — a customised template is never touched
  desc "Make the cast notification templates act-aware (idempotent, safe to re-run)"
  task act_aware_casting_templates: :environment do
    ActAwareCastingTemplates.apply!.each { |line| puts line }
  end

  module ActAwareCastingTemplates
    NEW_VARIABLES = [
      { "name" => "role_name", "description" => "What they were cast as — the role name, or \"Act 3 · Magic\" in an act-based production" },
      { "name" => "role_names", "description" => "All of their roles/acts across the linked shows, comma-separated" },
      { "name" => "casting_unit", "description" => "The word for the thing they were given: \"role\", or \"act\" in an act-based production" },
      { "name" => "casting_units", "description" => "Plural of casting_unit: \"roles\" or \"acts\"" }
    ].freeze

    TEMPLATES = {
      "cast_notification" => {
        name: "Cast Notification",
        subject: "Cast Confirmation: {{production_name}} - {{show_dates}}",
        seeded_body: <<~HTML,
          <p>You have been cast for {{production_name}}:</p>
          <ul>
          {{shows_list}}
          </ul>
          <p>Please let us know if you have any scheduling conflicts or questions.</p>
        HTML
        new_body: <<~HTML
          <p>You have been cast for {{production_name}}:</p>
          <ul>
          {{shows_list}}
          </ul>
          <p>Your {{casting_unit}} assignment: {{role_names}}</p>
          <p>Please let us know if you have any scheduling conflicts or questions.</p>
        HTML
      },
      "removed_from_cast_notification" => {
        name: "Removed from Cast Notification",
        subject: "Casting Update - {{production_name}} - {{show_dates}}",
        # The seeded wording never named the unit, so it stays as it is; the
        # variables are registered so a producer can add {{casting_unit}} themselves.
        seeded_body: <<~HTML,
          <p>There has been a change to the casting for {{production_name}}.</p>
          <p>You are no longer cast for:</p>
          <ul>
          {{shows_list}}
          </ul>
          <p>If you have any questions, please contact us.</p>
        HTML
        new_body: nil
      }
    }.freeze

    module_function

    def apply!
      TEMPLATES.map do |key, spec|
        template = ContentTemplate.find_or_initialize_by(key: key)
        lines = []

        default_body = (spec[:new_body] || spec[:seeded_body]).strip

        if template.new_record?
          template.assign_attributes(
            name: spec[:name],
            subject: spec[:subject],
            body: default_body,
            category: "casting",
            channel: "message",
            template_type: "hybrid",
            active: true
          )
          lines << "created"
        elsif spec[:new_body].nil?
          lines << "body unchanged (no new default)"
        elsif normalize(template.body) == normalize(spec[:seeded_body])
          template.body = default_body
          lines << "body updated (was the seeded default)"
        else
          lines << "body left as is (customised)"
        end

        merged = merge_variables(template.available_variables, NEW_VARIABLES)
        if merged != template.available_variables
          template.available_variables = merged
          lines << "variables registered"
        end

        template.save! if template.changed?
        "content template #{key}: #{lines.join(', ')}"
      end
    end

    def normalize(html)
      html.to_s.gsub(/\s+/, " ").strip
    end

    # Adds any variable not already present (by name); keeps existing entries
    # (and their descriptions) exactly as they are.
    def merge_variables(existing, additions)
      list = Array(existing).map { |v| v.is_a?(Hash) ? v.stringify_keys : { "name" => v.to_s } }
      names = list.map { |v| v["name"] }
      additions.each { |v| list << v unless names.include?(v["name"]) }
      list
    end
  end
end
