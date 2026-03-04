class FixVacancyInvitationTemplateSubject < ActiveRecord::Migration[8.1]
  def up
    template = ContentTemplate.find_by(key: "vacancy_invitation")
    return unless template

    # Update subject to use variables that are actually provided by the mailer/controller
    template.update!(
      subject: "Replacement needed for {{role_name}} — {{production_name}}",
      available_variables: [
        { name: "production_name", description: "Production name" },
        { name: "role_name", description: "Role name" },
        { name: "claim_url", description: "Link to claim the vacancy" },
        { name: "shows_list", description: "HTML list of show dates/times" },
        { name: "show_date", description: "Show date and time" },
        { name: "event_name", description: "Event/show name" },
        { name: "show_name", description: "Show name" },
        { name: "show_info", description: "Show date and name combined" },
        { name: "recipient_name", description: "Recipient's first name" }
      ]
    )
  end

  def down
    template = ContentTemplate.find_by(key: "vacancy_invitation")
    return unless template

    template.update!(
      subject: "You're invited to fill a role in {{production_name}}"
    )
  end
end
