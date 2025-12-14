# frozen_string_literal: true

class VacancyNotificationJob < ApplicationJob
  queue_as :default

  # Notify team members about a vacancy event
  # @param vacancy_id [Integer] The ID of the RoleVacancy
  # @param event [String] The type of event: "created" or "filled"
  # @param sender_user_id [Integer, nil] The ID of the user who triggered the event (for batch tracking)
  def perform(vacancy_id, event, sender_user_id = nil)
    vacancy = RoleVacancy.find_by(id: vacancy_id)
    return unless vacancy

    production = vacancy.show&.production
    return unless production

    # Find all team members with notifications enabled for this production
    recipients = find_notifiable_users(production)

    # If the vacancy was created by someone in a group being vacated, also notify group members
    if event == "created" && vacancy.vacated_by.is_a?(Group)
      group_member_users = vacancy.vacated_by.group_memberships
                                  .includes(person: :user)
                                  .select(&:notifications_enabled?)
                                  .map { |gm| gm.person.user }
                                  .compact
      recipients.concat(group_member_users)
    end

    recipients.uniq!
    return if recipients.empty?

    # Create an email batch if we have multiple recipients and a sender
    sender_user = User.find_by(id: sender_user_id) if sender_user_id
    sender_user ||= vacancy.closed_by || vacancy.created_by # Fallback to vacancy user

    email_batch = nil
    if recipients.size > 1 && sender_user
      role = vacancy.role
      show = vacancy.show
      subject = case event
      when "created"
        "[#{production.name}] New vacancy: #{role.name} for #{show.date_and_time.strftime('%b %-d')}"
      when "filled"
        "[#{production.name}] Vacancy filled: #{role.name} for #{show.date_and_time.strftime('%b %-d')}"
      else
        "[#{production.name}] Vacancy update: #{role.name}"
      end

      email_batch = EmailBatch.create!(
        user: sender_user,
        subject: subject,
        recipient_count: recipients.size,
        sent_at: Time.current
      )
    end

    recipients.each do |user|
      mailer_params = { vacancy: vacancy, user: user, event: event }
      mailer_params[:email_batch_id] = email_batch.id if email_batch

      VacancyNotificationMailer.with(mailer_params)
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
