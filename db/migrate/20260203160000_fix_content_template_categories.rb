# frozen_string_literal: true

class FixContentTemplateCategories < ActiveRecord::Migration[8.1]
  def up
    # Move audition-related templates to "signups" category
    %w[
      audition_invitation
      audition_added_to_cast
      audition_not_cast
      audition_not_invited
      audition_request_submitted
      talent_left_production
    ].each do |key|
      ContentTemplate.where(key: key).update_all(category: "signups")
    end

    # Move team invitations and group member added to "profiles" category
    %w[
      team_organization_invitation
      team_production_invitation
      group_member_added
    ].each do |key|
      ContentTemplate.where(key: key).update_all(category: "profiles")
    end

    # Fix any other miscategorized templates
    # person_invitation and group_invitation should also be in profiles (inviting people to join)
    %w[
      person_invitation
      group_invitation
      shoutout_notification
    ].each do |key|
      ContentTemplate.where(key: key).update_all(category: "profiles")
    end

    # Questionnaire invitations should be in signups
    ContentTemplate.where(key: "questionnaire_invitation").update_all(category: "signups")

    # Vacancy invitation should be in shows
    ContentTemplate.where(key: "vacancy_invitation").update_all(category: "shows")

    # Fix sign_up_registration_notification to be "both" channel (email + message)
    ContentTemplate.where(key: "sign_up_registration_notification").update_all(channel: "both")
  end

  def down
    # Revert to original categories
    %w[
      audition_invitation
      audition_added_to_cast
      audition_not_cast
      audition_not_invited
      audition_request_submitted
      talent_left_production
    ].each do |key|
      ContentTemplate.where(key: key).update_all(category: "casting")
    end

    %w[
      team_organization_invitation
      team_production_invitation
      person_invitation
      group_invitation
    ].each do |key|
      ContentTemplate.where(key: key).update_all(category: "invitations")
    end

    ContentTemplate.where(key: "group_member_added").update_all(category: "groups")
    ContentTemplate.where(key: "shoutout_notification").update_all(category: "notifications")
    ContentTemplate.where(key: "questionnaire_invitation").update_all(category: "questionnaires")
    ContentTemplate.where(key: "vacancy_invitation").update_all(category: "vacancies")
    ContentTemplate.where(key: "sign_up_registration_notification").update_all(channel: "message")
  end
end
