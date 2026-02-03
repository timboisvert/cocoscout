class PopulateContentTemplateAvailableVariables < ActiveRecord::Migration[8.1]
  # Populate available_variables for all ContentTemplates based on what the code actually passes.
  # This ensures templates are self-documenting and the admin UI can show available variables.

  TEMPLATE_VARIABLES = {
    # Auth
    "auth_welcome" => %w[name],
    "auth_password_reset" => %w[reset_url],

    # Profiles/People
    "person_invitation" => %w[organization_name setup_url accept_url custom_message],
    "group_invitation" => %w[group_name inviter_name accept_url custom_message],
    "group_member_added" => %w[recipient_name group_name added_by_name group_url custom_message],
    "shoutout_notification" => %w[recipient_name author_name shoutout_message shoutout_url],
    "shoutout_invitation" => %w[author_name setup_url],

    # Team
    "team_organization_invitation" => %w[organization_name inviter_name accept_url custom_message],
    "team_production_invitation" => %w[production_name inviter_name accept_url custom_message],

    # Sign-ups
    "sign_up_confirmation" => %w[registrant_name sign_up_form_name slot_name show_name show_date production_name],
    "sign_up_queued" => %w[registrant_name sign_up_form_name slot_name show_name show_date production_name],
    "sign_up_slot_assigned" => %w[registrant_name sign_up_form_name slot_name show_name show_date production_name],
    "sign_up_slot_changed" => %w[registrant_name sign_up_form_name slot_name show_name show_date production_name],
    "sign_up_cancelled" => %w[registrant_name sign_up_form_name slot_name show_name show_date production_name],
    "sign_up_registration_notification" => %w[registrant_name recipient_name sign_up_form_name slot_name event_info registrations_url production_name],

    # Auditions
    "audition_invitation" => %w[recipient_name production_name audition_cycle_name],
    "audition_not_invited" => %w[recipient_name production_name],
    "audition_request_submitted" => %w[recipient_name requestable_name production_name review_url],
    "talent_left_production" => %w[talent_name recipient_name production_name groups_removed talent_pool_url],
    "questionnaire_invitation" => %w[person_name questionnaire_title production_name questionnaire_url custom_message],
    "audition_added_to_cast" => %w[recipient_name production_name talent_pool_name confirm_by_date],
    "audition_not_cast" => %w[recipient_name production_name],

    # Casting
    "cast_notification" => %w[production_name show_dates shows_list],
    "removed_from_cast_notification" => %w[production_name show_dates shows_list],
    "casting_table_notification" => %w[person_name production_names shows_by_production],

    # Shows
    "show_canceled" => %w[recipient_name production_name event_type event_date show_name location],
    "vacancy_invitation" => %w[production_name role_name event_name show_date show_info],
    "vacancy_invitation_linked" => %w[production_name role_name show_count shows_list],
    "vacancy_created" => %w[role_name show_date production_name show_url vacancy_url person_name recipient_name],
    "vacancy_filled" => %w[role_name show_date production_name show_url vacancy_url person_name filled_by_name recipient_name],
    "vacancy_reclaimed" => %w[role_name show_date production_name show_url vacancy_url person_name recipient_name],

    # Payments
    "payment_setup_reminder" => %w[person_name organization_name production_name payment_setup_url custom_message],

    # Messages
    "unread_digest" => %w[recipient_name inbox_url thread_list]
  }.freeze

  def up
    TEMPLATE_VARIABLES.each do |key, variables|
      template = ContentTemplate.find_by(key: key)
      next unless template

      # Build array of variable hashes with name and description
      variable_data = variables.map do |var|
        { name: var, description: describe_variable(var) }
      end

      template.update!(available_variables: variable_data)
    end
  end

  def down
    TEMPLATE_VARIABLES.keys.each do |key|
      template = ContentTemplate.find_by(key: key)
      template&.update!(available_variables: nil)
    end
  end

  private

  def describe_variable(var)
    descriptions = {
      # Common
      "name" => "Recipient's name",
      "recipient_name" => "Recipient's first name",
      "person_name" => "Person's full name",

      # URLs
      "reset_url" => "Password reset link",
      "setup_url" => "Account setup link",
      "accept_url" => "Invitation acceptance link",
      "inbox_url" => "Link to message inbox",
      "questionnaire_url" => "Link to questionnaire",
      "talent_pool_url" => "Link to talent pool",
      "show_url" => "Link to show details",
      "vacancy_url" => "Link to vacancy details",
      "registrations_url" => "Link to registrations list",
      "payment_setup_url" => "Link to payment setup",

      # Organizations/Productions
      "organization_name" => "Organization name",
      "production_name" => "Production name",
      "production_names" => "List of production names",

      # People
      "author_name" => "Name of the author/sender",
      "inviter_name" => "Name of person who sent invitation",
      "talent_name" => "Talent/performer's name",
      "added_by_name" => "Name of person who added the member",
      "filled_by_name" => "Name of person who filled the vacancy",
      "registrant_name" => "Name of the person who registered",
      "requestable_name" => "Name of the person who submitted the request",

      # Groups
      "group_name" => "Group name",
      "group_url" => "Link to the group page",
      "groups_removed" => "List of groups the person was removed from",

      # Shows/Events
      "show_name" => "Show/event name",
      "show_date" => "Show date and time",
      "show_dates" => "Range of show dates",
      "event_name" => "Event name",
      "event_type" => "Type of event (show, rehearsal, etc.)",
      "event_date" => "Event date and time",
      "event_info" => "Event details summary",
      "location" => "Event location",

      # Casting
      "role_name" => "Role name",
      "shows_list" => "HTML list of shows",
      "shows_by_production" => "Shows organized by production",
      "talent_pool_name" => "Name of the talent pool",
      "confirm_by_date" => "Deadline to confirm casting",
      "show_count" => "Number of shows",

      # Sign-ups
      "sign_up_form_name" => "Sign-up form name",
      "slot_name" => "Time slot name",

      # Auditions
      "audition_cycle_name" => "Name of the audition cycle",
      "questionnaire_title" => "Questionnaire title",
      "review_url" => "Link to review the submission",

      # Content
      "shoutout_message" => "The shoutout message content",
      "shoutout_url" => "Link to view the shoutout/profile",
      "custom_message" => "Custom message from sender",
      "thread_list" => "List of unread message threads"
    }

    descriptions[var] || var.humanize
  end
end
