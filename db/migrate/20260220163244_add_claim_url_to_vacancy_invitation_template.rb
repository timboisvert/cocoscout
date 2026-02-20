class AddClaimUrlToVacancyInvitationTemplate < ActiveRecord::Migration[8.1]
  def up
    template = ContentTemplate.find_by(key: "vacancy_invitation")
    return unless template

    # Add claim_url to available_variables
    current_vars = template.available_variables || []
    unless current_vars.any? { |v| v["name"] == "claim_url" || v[:name] == "claim_url" }
      current_vars << { name: "claim_url", description: "Link to claim the vacancy" }
      template.available_variables = current_vars
    end

    # Update body to include the claim link
    template.body = <<~HTML
      <p>A replacement is needed for the {{role_name}} role in {{production_name}}.</p>
      <p>Show: {{show_info}}</p>
      <p>Role: {{role_name}}</p>
      <p>If you're available and interested, click the link below to claim this spot.</p>
      <p><a href="{{claim_url}}" style="display: inline-block; background-color: #ec4899; color: white; padding: 12px 24px; border-radius: 6px; text-decoration: none; font-weight: 500;">Claim This Role</a></p>
      <p>Thank you,<br>{{production_name}}</p>
    HTML

    template.save!
  end

  def down
    template = ContentTemplate.find_by(key: "vacancy_invitation")
    return unless template

    # Remove claim_url from available_variables
    current_vars = template.available_variables || []
    current_vars.reject! { |v| v["name"] == "claim_url" || v[:name] == "claim_url" }
    template.available_variables = current_vars

    # Revert body to version without link
    template.body = <<~HTML
      <p>A replacement is needed for the {{role_name}} role in {{production_name}}.</p>
      <p>Show: {{show_info}}</p>
      <p>Role: {{role_name}}</p>
      <p>If you're available and interested, click the link below to claim this spot.</p>
      <p>Thank you,<br>{{production_name}}</p>
    HTML

    template.save!
  end
end
