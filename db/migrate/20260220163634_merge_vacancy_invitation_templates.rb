class MergeVacancyInvitationTemplates < ActiveRecord::Migration[8.1]
  def up
    template = ContentTemplate.find_by(key: "vacancy_invitation")
    return unless template

    # Update available_variables - simplified to always use shows_list
    template.available_variables = [
      { name: "production_name", description: "Production name" },
      { name: "role_name", description: "Role name" },
      { name: "claim_url", description: "Link to claim the vacancy" },
      { name: "shows_list", description: "HTML list of show dates/times" }
    ]

    # Email body - always uses shows_list
    template.body = <<~HTML
      <p>A replacement is needed for the {{role_name}} role in {{production_name}}.</p>
      <p>{{shows_list}}</p>
      <p>If you're available and interested, click the button below to claim this spot.</p>
      <p><a href="{{claim_url}}" style="display: inline-block; background-color: #ec4899; color: white; padding: 12px 24px; border-radius: 6px; text-decoration: none; font-weight: 500;">Claim This Role</a></p>
      <p>Thank you,<br>{{production_name}}</p>
    HTML

    # Message body - always uses shows_list
    template.message_body = <<~HTML
      <div>A replacement is needed for the <strong>{{role_name}}</strong> role in <strong>{{production_name}}</strong>.<br><br>{{shows_list}}<br><br>If you're available and interested, click the link below to claim this spot.<br><br><a href="{{claim_url}}">Claim This Role</a><br><br>Thank you,<br>{{production_name}}</div>
    HTML

    template.save!

    # Delete the linked template - no longer needed
    ContentTemplate.where(key: "vacancy_invitation_linked").destroy_all
  end

  def down
    # Restore vacancy_invitation to previous version
    template = ContentTemplate.find_by(key: "vacancy_invitation")
    if template
      template.available_variables = [
        { name: "production_name", description: "Production name" },
        { name: "role_name", description: "Role name" },
        { name: "event_name", description: "Event name" },
        { name: "show_date", description: "Show date and time" },
        { name: "show_info", description: "Show info" },
        { name: "claim_url", description: "Link to claim the vacancy" }
      ]

      template.body = <<~HTML
        <p>A replacement is needed for the {{role_name}} role in {{production_name}}.</p>
        <p>Show: {{show_info}}</p>
        <p>If you're available and interested, click the link below to claim this spot.</p>
        <p><a href="{{claim_url}}" style="display: inline-block; background-color: #ec4899; color: white; padding: 12px 24px; border-radius: 6px; text-decoration: none; font-weight: 500;">Claim This Role</a></p>
        <p>Thank you,<br>{{production_name}}</p>
      HTML

      template.message_body = <<~HTML
        <div>A replacement is needed for the {{role_name}} role in {{production_name}}.<br><br>Show: {{show_info}}<br><br>If you're available and interested, click the link below to claim this spot.<br><br><a href="{{claim_url}}">Claim This Role</a><br><br>Thank you,<br>{{production_name}}</div>
      HTML

      template.save!
    end

    # Recreate vacancy_invitation_linked
    ContentTemplate.find_or_create_by!(key: "vacancy_invitation_linked") do |t|
      t.name = "Vacancy Invitation (Linked Shows)"
      t.description = "Sent when inviting someone to fill a role vacancy across linked shows"
      t.category = "shows"
      t.channel = "both"
      t.subject = "You're invited to fill a role in {{production_name}}"
      t.body = <<~HTML
        <p>A replacement is needed for the {{role_name}} role in {{production_name}}.</p>
        <p>Shows ({{show_count}} linked events):</p>
        <p>{{shows_list}}</p>
        <p>Role: {{role_name}}</p>
        <p>If you're available and interested, click the link below to claim this spot.</p>
        <p>Thank you,<br>{{production_name}}</p>
      HTML
      t.message_body = <<~HTML
        <div>A replacement is needed for the <strong>{{role_name}}</strong> role in <strong>{{production_name}}</strong>.<br><br>Shows:<br>{{shows_list}}<br><br>Role:&nbsp;<br>{{role_name}}<br><br>If you're available and interested, click the link below to claim this spot.<br><br>Thank you,<br>{{production_name}}</div>
      HTML
      t.available_variables = [
        { name: "production_name", description: "Production name" },
        { name: "role_name", description: "Role name" },
        { name: "show_count", description: "Number of linked shows" },
        { name: "shows_list", description: "HTML list of all linked show dates/times" }
      ]
    end
  end
end
