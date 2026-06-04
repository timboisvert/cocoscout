# frozen_string_literal: true

# Four ContentTemplates that Mics::NotificationService renders when a
# new submission / claim / challenge / suggestion lands in the queue.
# Each goes out as an in-app message to the affected hub's captains
# (or all superadmins when the hub has no captain).
class AddMicQueueNotificationTemplates < ActiveRecord::Migration[8.1]
  TEMPLATES = [
    {
      key: "mic_submission_filed",
      name: "New mic submitted to the finder queue",
      subject: "New mic submission: {{mic_name}} ({{venue_city}})",
      body: <<~BODY,
        A new mic has been submitted and is waiting for review.

        **{{mic_name}}**
        {{venue_name}} · {{venue_city}}

        Submitted by: {{submitter}}

        [Open the mics queue]({{queue_url}})
      BODY
      available_variables: [
        { "name" => "mic_name",   "description" => "Submitted mic's name" },
        { "name" => "venue_name", "description" => "Venue name" },
        { "name" => "venue_city", "description" => "Neighborhood + city" },
        { "name" => "submitter",  "description" => "Email of the submitter, or anonymous" },
        { "name" => "queue_url",  "description" => "Link to the mics admin queue" }
      ]
    },
    {
      key: "mic_claim_filed",
      name: "Mic claim filed",
      subject: "Claim filed on {{mic_name}}",
      body: <<~BODY,
        Someone wants to claim **{{mic_name}}** ({{venue_name}}, {{venue_city}}).

        - Claimant: {{claimant}}
        - Requested role: **{{role}}**
        - Reason: {{reason}}

        [Open the mics queue]({{queue_url}})
      BODY
      available_variables: [
        { "name" => "mic_name",   "description" => "Mic being claimed" },
        { "name" => "venue_name", "description" => "Venue name" },
        { "name" => "venue_city", "description" => "Neighborhood + city" },
        { "name" => "claimant",   "description" => "Email of the claimant" },
        { "name" => "role",       "description" => "Requested role (producer, co-producer, host)" },
        { "name" => "reason",     "description" => "Claimant's note" },
        { "name" => "queue_url",  "description" => "Link to the mics admin queue" }
      ]
    },
    {
      key: "mic_challenge_filed",
      name: "Mic ownership challenge filed",
      subject: "Ownership challenge on {{mic_name}}",
      body: <<~BODY,
        Someone is challenging the current owner of **{{mic_name}}** ({{venue_name}}, {{venue_city}}).

        - Challenger: {{challenger}}
        - Current lead: {{current_lead}}
        - Reason: {{reason}}

        [Open the mics queue]({{queue_url}})
      BODY
      available_variables: [
        { "name" => "mic_name",     "description" => "Mic being challenged" },
        { "name" => "venue_name",   "description" => "Venue name" },
        { "name" => "venue_city",   "description" => "Neighborhood + city" },
        { "name" => "challenger",   "description" => "Email of the challenger" },
        { "name" => "current_lead", "description" => "Email of the current lead, if any" },
        { "name" => "reason",       "description" => "Challenger's note" },
        { "name" => "queue_url",    "description" => "Link to the mics admin queue" }
      ]
    },
    {
      key: "mic_suggestion_filed",
      name: "Mic edit suggestion filed",
      subject: "Edit suggested for {{mic_name}}",
      body: <<~BODY,
        Someone in the community suggested an edit to **{{mic_name}}** ({{venue_name}}, {{venue_city}}).

        From: {{submitter}}

        > {{note}}

        [Open the mics queue]({{queue_url}})
      BODY
      available_variables: [
        { "name" => "mic_name",   "description" => "Mic being edited" },
        { "name" => "venue_name", "description" => "Venue name" },
        { "name" => "venue_city", "description" => "Neighborhood + city" },
        { "name" => "submitter",  "description" => "Email of the submitter, or anonymous" },
        { "name" => "note",       "description" => "The suggestion text" },
        { "name" => "queue_url",  "description" => "Link to the mics admin queue" }
      ]
    }
  ].freeze

  def up
    TEMPLATES.each do |attrs|
      next if ContentTemplate.exists?(key: attrs[:key])
      ContentTemplate.create!(
        key: attrs[:key],
        name: attrs[:name],
        subject: attrs[:subject],
        body: attrs[:body],
        category: "mics",
        channel: "message",
        template_type: "structured",
        active: true,
        available_variables: attrs[:available_variables]
      )
    end
  end

  def down
    TEMPLATES.each { |attrs| ContentTemplate.find_by(key: attrs[:key])&.destroy }
  end
end
