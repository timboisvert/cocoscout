# frozen_string_literal: true

# Single source of truth for asking people to sign a production's agreement.
# Delivers the request (via MessageService, rendered from the seeded
# `request_agreement_signature` ContentTemplate — never hardcoded copy) and
# records an AgreementRequest per person so the producer's roster can show who
# has been sent the agreement.
#
# Used both by the manual "send to unsigned" producer action and by the
# automatic on-talent-pool-add path (see TalentPoolMembership).
class AgreementRequestService
  class << self
    # Send the request to specific people for a production.
    # Returns the number of people actually contacted (those with an account).
    def send_to(production:, people:, sent_by: nil)
      return 0 unless production.agreement_template.present?

      # Only people with a login can receive the message; those still on an
      # invitation get the agreement when they accept and sign in.
      already_signed = production.agreement_signatures.pluck(:person_id).to_set
      targets = Array(people).uniq.select do |p|
        p.is_a?(Person) && p.user.present? && !already_signed.include?(p.id)
      end
      return 0 if targets.empty?

      sender = sent_by || production.organization.owner
      url = agreement_url_for(production)

      targets.each do |person|
        deliver(production: production, person: person, sender: sender, url: url)
        AgreementRequest.record!(production: production, person: person, sent_by: sent_by)
      end

      targets.size
    end

    # Fired when a Person is added to a talent pool: send the agreement for any
    # production that uses this pool and has auto-send enabled. Best-effort — a
    # messaging failure must never block adding someone to a pool.
    def auto_send_for_new_member(talent_pool:, person:)
      return unless person.is_a?(Person)

      talent_pool.all_productions.each do |production|
        next unless production.agreement_required? && production.agreement_auto_send?
        next if AgreementRequest.exists?(production: production, person: person)

        send_to(production: production, people: [ person ])
      end
    rescue StandardError => e
      Rails.logger.error("[AgreementRequestService] auto-send failed for person #{person&.id}: #{e.class}: #{e.message}")
    end

    private

    def deliver(production:, person:, sender:, url:)
      rendered = ContentTemplateService.render("request_agreement_signature", {
        recipient_name: person.name,
        production_name: production.name,
        agreement_url: url
      })

      # In-app message only — never an email (skip_digest). Rendered from the
      # seeded request_agreement_signature ContentTemplate.
      MessageService.send_direct(
        sender: sender,
        recipient_person: person,
        subject: rendered[:subject],
        body: rendered[:body],
        organization: production.organization,
        production: production,
        system_generated: true,
        skip_digest: true
      )
    end

    def agreement_url_for(production)
      Rails.application.routes.url_helpers.my_production_agreement_url(
        production,
        host: Rails.application.config.action_mailer.default_url_options[:host]
      )
    end
  end
end
