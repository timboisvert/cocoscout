# frozen_string_literal: true

# The words of the notifications about a request for more comps on one date
# (CompRequestNotices; Tim, 2026-11-20). Each is a seeded ContentTemplate and
# a notification only, never an email: the Notifications list and a push.
# The subject is what the notification says; the body is kept for the
# template's editor and says the same.
class CompRequestTemplates
  VARIABLES = [
    { "name" => "production_name", "description" => "The production" },
    { "name" => "date_words", "description" => "The date and time, e.g. Friday, November 27 at 8:00 PM" },
    { "name" => "more_comps", "description" => "What was requested, e.g. 4 more comps" }
  ].freeze

  TEMPLATES = [
    { key: "comp_request_requested", name: "Comps: more requested for a date (to the organization's managers)",
      subject: "{{requester_name}} requested {{more_comps}}: {{production_name}}, {{date_words}}",
      body: %(<p>{{requester_name}} requested {{more_comps}} for {{production_name}}, {{date_words}}, for {{side_words}}.</p>{{#note}}<p>"{{note}}"</p>{{/note}}<p><a href="{{listing_url}}">Open the date</a></p>),
      variables: VARIABLES + [
        { "name" => "requester_name", "description" => "Who requested them" },
        { "name" => "side_words", "description" => "the people on the contract, or the production team" },
        { "name" => "note", "description" => "Their note, if any" },
        { "name" => "listing_url", "description" => "The date's page in Ticketing" } ] },
    { key: "comp_request_approved", name: "Comps: a request approved (to whoever requested them)",
      subject: "{{organization_name}} approved {{approved_words}}: {{production_name}}, {{date_words}}{{#comment}}. Their comment: \"{{comment}}\"{{/comment}}",
      body: %(<p>{{organization_name}} approved {{approved_words}} for {{production_name}}, {{date_words}}.</p>{{#comment}}<p>"{{comment}}"</p>{{/comment}}<p><a href="{{comps_url}}">Open the date</a></p>),
      variables: VARIABLES + [
        { "name" => "organization_name", "description" => "The organization that decided it" },
        { "name" => "approved_words", "description" => "e.g. your request for 4 more comps, or 2 of the 4 more comps you requested" },
        { "name" => "comment", "description" => "Their comment, if any" },
        { "name" => "comps_url", "description" => "Where the requester issues comps for the date" } ] },
    { key: "comp_request_declined", name: "Comps: a request declined (to whoever requested them)",
      subject: "{{organization_name}} declined your request for {{more_comps}}: {{production_name}}, {{date_words}}{{#comment}}. Their comment: \"{{comment}}\"{{/comment}}",
      body: %(<p>{{organization_name}} declined your request for {{more_comps}} for {{production_name}}, {{date_words}}.</p>{{#comment}}<p>"{{comment}}"</p>{{/comment}}<p><a href="{{comps_url}}">Open the date</a></p>),
      variables: VARIABLES + [
        { "name" => "organization_name", "description" => "The organization that decided it" },
        { "name" => "comment", "description" => "Their comment, if any" },
        { "name" => "comps_url", "description" => "Where the requester issues comps for the date" } ] },
    { key: "comp_request_closed", name: "Comps: a request closed without a decision (to whoever requested them)",
      subject: "Your request for {{more_comps}} for {{production_name}}, {{date_words}}, was closed: {{closed_words}}",
      body: %(<p>Your request for {{more_comps}} for {{production_name}}, {{date_words}}, was closed: {{closed_words}}.</p><p><a href="{{comps_url}}">Open the date</a></p>),
      variables: VARIABLES + [
        { "name" => "closed_words", "description" => "Why, e.g. the date started before anyone decided it" },
        { "name" => "comps_url", "description" => "Where the requester issues comps for the date" } ] }
  ].freeze

  def self.ensure!(keys: nil, overwrite: false)
    TEMPLATES.each do |spec|
      next if keys && !keys.include?(spec[:key])

      template = ContentTemplate.find_or_initialize_by(key: spec[:key])
      next if template.persisted? && !overwrite

      template.assign_attributes(name: spec[:name], category: "ticketing", channel: "message", template_type: "structured",
                                 active: true, subject: spec[:subject], body: spec[:body], available_variables: spec[:variables])
      template.save!
    end
  end
end
