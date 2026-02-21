class UpdateAuditionInvitationAvailableVariables < ActiveRecord::Migration[8.1]
  def up
    template = ContentTemplate.find_by(key: "audition_invitation")
    return unless template

    # Add new variables for audition session details and acceptance link
    new_variables = %w[
      recipient_name
      production_name
      audition_cycle_name
      audition_date
      audition_time
      audition_location
      audition_url
    ]

    template.update!(available_variables: new_variables)
  end

  def down
    template = ContentTemplate.find_by(key: "audition_invitation")
    return unless template

    # Revert to original variables
    template.update!(available_variables: %w[recipient_name production_name audition_cycle_name])
  end
end
