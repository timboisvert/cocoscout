# frozen_string_literal: true

# Notifies the right humans when something happens in the Mics Finder
# queue. The rule is simple — the affected mic's hub captain hears
# first; if the hub has no captain, every superadmin hears instead
# (since superadmins are the implicit captains for uncaptained hubs).
#
# Four events fan out: submission, claim, challenge, suggestion. Each
# uses its own ContentTemplate so the copy is editable from the
# superadmin templates surface.
module Mics
  class NotificationService
    class << self
      def notify_submission(mic:)
        deliver(
          mic: mic,
          template_key: "mic_submission_filed",
          actor: submission_actor(mic),
          variables: {
            mic_name:       mic.name,
            venue_name:     mic.venue&.name.to_s,
            venue_city:     mic.venue&.neighborhood_city.to_s,
            submitter:      submission_actor(mic)&.email_address.to_s.presence || "an anonymous visitor",
            queue_url:      queue_url
          }
        )
      end

      def notify_claim(claim:)
        deliver(
          mic: claim.mic,
          template_key: "mic_claim_filed",
          actor: claim.claimant,
          variables: {
            mic_name:    claim.mic.name,
            venue_name:  claim.mic.venue&.name.to_s,
            venue_city:  claim.mic.venue&.neighborhood_city.to_s,
            claimant:    claim.claimant&.email_address.to_s,
            role:        claim.role.to_s.humanize,
            reason:      claim.reason.to_s.presence || "(no reason given)",
            queue_url:   queue_url
          }
        )
      end

      def notify_challenge(challenge:)
        deliver(
          mic: challenge.mic,
          template_key: "mic_challenge_filed",
          actor: challenge.challenger,
          variables: {
            mic_name:     challenge.mic.name,
            venue_name:   challenge.mic.venue&.name.to_s,
            venue_city:   challenge.mic.venue&.neighborhood_city.to_s,
            challenger:   challenge.challenger&.email_address.to_s,
            current_lead: challenge.target&.email_address.to_s.presence || "(no current lead)",
            reason:       challenge.reason.to_s.presence || "(no reason given)",
            queue_url:    queue_url
          }
        )
      end

      def notify_suggestion(suggestion:)
        deliver(
          mic: suggestion.mic,
          template_key: "mic_suggestion_filed",
          actor: suggestion.submitter,
          variables: {
            mic_name:    suggestion.mic.name,
            venue_name:  suggestion.mic.venue&.name.to_s,
            venue_city:  suggestion.mic.venue&.neighborhood_city.to_s,
            submitter:   suggestion.submitter&.email_address.to_s.presence || suggestion.submitter_email.to_s.presence || "an anonymous visitor",
            note:        suggestion.note.to_s,
            queue_url:   queue_url
          }
        )
      end

      private

      # Render + ship to every relevant recipient. Failures are logged
      # but never raised — a missing template should not block the user
      # action that triggered the notification.
      def deliver(mic:, template_key:, actor:, variables:)
        recipients = recipient_people_for(mic)
        return { messages_sent: 0 } if recipients.empty?

        unless ContentTemplateService.exists?(template_key)
          Rails.logger.warn "[MicsNotification] template missing: #{template_key}"
          return { messages_sent: 0 }
        end

        rendered = ContentTemplateService.render(template_key, variables)
        sender   = sender_user(actor)
        return { messages_sent: 0 } unless sender

        sent = 0
        recipients.each do |person|
          message = MessageService.send_direct(
            sender:           sender,
            recipient_person: person,
            subject:          rendered[:subject],
            body:             rendered[:body],
            system_generated: true
          )
          sent += 1 if message
        end
        { messages_sent: sent }
      rescue StandardError => e
        Rails.logger.error "[MicsNotification] #{template_key} failed: #{e.class}: #{e.message}"
        { messages_sent: 0 }
      end

      # Recipients are city-hub captains for the affected mic's hub —
      # or, if the hub has no captain (or no hub exists), all superadmins
      # acting as the implicit captains.
      def recipient_people_for(mic)
        hub = mic.venue&.city_hub
        captain_users =
          if hub
            User.joins("INNER JOIN city_hub_memberships chm ON chm.user_id = users.id")
                .where(chm: { city_hub_id: hub.id, role: CityHubMembership.roles[:editor] })
                .distinct
          else
            User.none
          end

        users = captain_users.exists? ? captain_users.to_a : superadmin_users
        users.filter_map(&:primary_person).uniq
      end

      # Sender is the user who triggered the action (so the captain sees
      # "from <submitter>" in their inbox); falls back to a superadmin
      # when the trigger was anonymous (suggestions without an account).
      def sender_user(actor)
        return actor if actor.is_a?(User)
        superadmin_users.first
      end

      # `superadmin?` is a method on User backed by a hardcoded email
      # allowlist, not a column — so we look users up by that allowlist
      # rather than `User.where(superadmin: true)`.
      def superadmin_users
        emails = User.const_get(:SUPERADMIN_EMAILS).map(&:downcase)
        User.where("LOWER(email_address) IN (?)", emails).to_a
      end

      # The mic submitter doesn't get persisted on the Mic itself —
      # pull it from the first MicEdit row for the submission.
      def submission_actor(mic)
        edit = mic.mic_edits.where(field: "submission").order(:created_at).first
        edit && User.find_by(id: edit.editor_user_id)
      end

      def queue_url
        Rails.application.routes.url_helpers.mics_index_path
      end
    end
  end
end
