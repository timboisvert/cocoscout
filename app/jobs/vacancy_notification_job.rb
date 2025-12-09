# frozen_string_literal: true

class VacancyNotificationJob < ApplicationJob
  queue_as :default

  # Notify team members about a vacancy event
  # @param vacancy_id [Integer] The ID of the RoleVacancy
  # @param event [String] The type of event: "created" or "filled"
  def perform(vacancy_id, event)
    vacancy = RoleVacancy.find_by(id: vacancy_id)
    return unless vacancy

    production = vacancy.show&.production
    return unless production

    # Find all team members with notifications enabled for this production
    recipients = find_notifiable_users(production)

    recipients.each do |user|
      VacancyNotificationMailer.with(vacancy: vacancy, user: user, event: event)
                               .vacancy_notification
                               .deliver_later
    end
  end

  private

  def find_notifiable_users(production)
    organization = production.organization
    users_with_production_permission_ids = production.production_permissions.pluck(:user_id)

    # Get users with explicit production permissions who have notifications enabled
    users_with_permissions = production.production_permissions
                                       .includes(:user)
                                       .select(&:notifications_enabled?)
                                       .map(&:user)

    # Get the organization owner if they don't have an explicit production permission
    # (owners default to receiving notifications)
    owner = organization.owner
    owner_without_explicit_permission = if owner && !users_with_production_permission_ids.include?(owner.id)
      [ owner ]
    else
      []
    end

    # Get users with global manager role who don't have a production permission
    # (they use the default which is notifications enabled for managers)
    users_with_global_manager = organization.organization_roles
                                            .where(company_role: "manager")
                                            .includes(:user)
                                            .map(&:user)

    # Filter global managers to those without explicit production permissions
    users_with_global_manager_only = users_with_global_manager.reject do |user|
      users_with_production_permission_ids.include?(user.id)
    end

    (users_with_permissions + owner_without_explicit_permission + users_with_global_manager_only).uniq
  end
end
