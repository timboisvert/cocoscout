# frozen_string_literal: true

# The words of visual asset requests (Tim, 2026-11-19), seeded as
# ContentTemplates (the ContractDateRequestTemplates pattern):
#   - the request email, which carries the manager's own subject and message
#     and the one button (EmailButton: class="button");
#   - three notifications, never emails: to people on the contract who have
#     an account when a request is sent, and to the production's managers as
#     things arrive (folded into one per sitting) and when everything
#     required has been added.
class VisualAssetTemplates
  BASE_VARIABLES = [
    { "name" => "organization_name", "description" => "The organization requesting" },
    { "name" => "production_name", "description" => "The production" }
  ].freeze

  TEMPLATES = [
    { key: "visual_assets_request", name: "Images and details requested (to the people it's sent to)", channel: "email",
      subject: "{{subject}}",
      body: %({{message_html}}<p><strong>What we need</strong></p>{{list_html}}) +
            %(<p><a href="{{upload_url}}" class="button">Upload your images</a></p>) +
            %(<p style="color:#6b7280;font-size:13px">You don't need an account. The page checks each file as you add it and tells you right away if a size is off.</p>) +
            %(<p style="color:#6b7280;font-size:13px">If someone else makes your artwork, forward them this email. The link works for them too, until the last date of the show.</p>) +
            %(<p style="color:#6b7280;font-size:13px">Sent by {{sender_name}} at {{organization_name}}.</p>),
      variables: BASE_VARIABLES + [
        { "name" => "subject", "description" => "The subject the manager wrote" },
        { "name" => "message_html", "description" => "The message the manager wrote, as paragraphs" },
        { "name" => "list_html", "description" => "What is still needed, as a list" },
        { "name" => "upload_url", "description" => "The no-login page" },
        { "name" => "sender_name", "description" => "The manager who sent it" } ] },
    { key: "visual_assets_requested", name: "Images and details requested (to people on the contract)", channel: "message",
      subject: "{{organization_name}} requested images and details for {{production_name}}",
      body: %(<p>{{organization_name}} requested images and details for {{production_name}}.</p>),
      variables: BASE_VARIABLES },
    { key: "visual_assets_arrived", name: "Images or details arrived (to the production's managers)", channel: "message",
      subject: "{{production_name}}: {{arrived_words}} {{count_words}}",
      body: %(<p>{{production_name}}: {{arrived_words}} {{count_words}}</p>),
      variables: BASE_VARIABLES + [
        { "name" => "arrived_words", "description" => "What arrived, e.g. Dana Whitfield added the Eventbrite banner, and replaced the Poster." },
        { "name" => "count_words", "description" => "e.g. 4 of 9 received." } ] },
    { key: "visual_assets_complete", name: "Everything required has been added (to the production's managers)", channel: "message",
      subject: "{{production_name}}: everything required has been added. {{arrived_words}} {{count_words}}",
      body: %(<p>{{production_name}}: everything required has been added. {{arrived_words}} {{count_words}}</p>),
      variables: BASE_VARIABLES + [
        { "name" => "arrived_words", "description" => "What arrived last" },
        { "name" => "count_words", "description" => "e.g. 6 of 9 received." } ] }
  ].freeze

  def self.ensure!(keys: nil, overwrite: false)
    TEMPLATES.each do |spec|
      next if keys && !keys.include?(spec[:key])

      template = ContentTemplate.find_or_initialize_by(key: spec[:key])
      next if template.persisted? && !overwrite

      template.assign_attributes(name: spec[:name], category: "shows", channel: spec[:channel], template_type: "structured",
                                 active: true, subject: spec[:subject], body: spec[:body], available_variables: spec[:variables])
      template.save!
    end
  end
end
