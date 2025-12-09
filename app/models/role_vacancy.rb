class RoleVacancy < ApplicationRecord
  belongs_to :show
  belongs_to :role
  belongs_to :vacated_by, polymorphic: true, optional: true
  belongs_to :filled_by, class_name: "Person", optional: true
  belongs_to :closed_by, class_name: "User", optional: true
  belongs_to :created_by, class_name: "User", optional: true

  has_many :invitations, class_name: "RoleVacancyInvitation", dependent: :destroy

  enum :status, { open: "open", filled: "filled", cancelled: "cancelled" }

  scope :for_show, ->(show) { where(show: show) }
  scope :for_role, ->(role) { where(role: role) }

  validates :status, presence: true

  # Invalidate production dashboard cache when vacancy changes
  after_commit :invalidate_dashboard_cache

  # Send notification to team when vacancy is created
  after_commit :notify_team_of_creation, on: :create

  def fill!(person, by: nil)
    transaction do
      # Remove the old cast assignment for the entity who vacated (Person or Group)
      if vacated_by.present?
        show.show_person_role_assignments
            .where(role: role, assignable_type: vacated_by_type, assignable_id: vacated_by_id)
            .destroy_all
      end

      # Create a new cast assignment for the person filling the vacancy
      show.show_person_role_assignments.create!(
        role: role,
        assignable: person
      )

      # Update the vacancy status
      update!(
        status: :filled,
        filled_by: person,
        filled_at: Time.current,
        closed_at: Time.current,
        closed_by: by
      )
    end

    # Notify team after the transaction completes
    VacancyNotificationJob.perform_later(id, "filled")
  end

  def cancel!(by: nil)
    update!(
      status: :cancelled,
      closed_at: Time.current,
      closed_by: by
    )
  end

  def can_invite?(person)
    open? && !invitations.exists?(person: person)
  end

  def pending_invitations
    invitations.pending
  end

  def claimed_invitation
    invitations.claimed.first
  end

  private

  def invalidate_dashboard_cache
    production = show&.production
    DashboardService.invalidate(production) if production
  end

  def notify_team_of_creation
    VacancyNotificationJob.perform_later(id, "created")
  end
end
