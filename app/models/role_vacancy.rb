class RoleVacancy < ApplicationRecord
  belongs_to :show
  belongs_to :role
  belongs_to :vacated_by, polymorphic: true, optional: true
  belongs_to :filled_by, class_name: "Person", optional: true
  belongs_to :closed_by, class_name: "User", optional: true
  belongs_to :created_by, class_name: "User", optional: true

  has_many :invitations, class_name: "RoleVacancyInvitation", dependent: :destroy
  has_many :role_vacancy_shows, dependent: :destroy
  has_many :affected_shows, through: :role_vacancy_shows, source: :show

  enum :status, { open: "open", filled: "filled", cancelled: "cancelled" }

  scope :for_show, ->(show) { where(show: show) }
  scope :for_role, ->(role) { where(role: role) }

  validates :status, presence: true
  validates :role, presence: true

  # Delegate to role for convenience
  delegate :name, to: :role, prefix: true
  delegate :restricted?, :eligible_members, :eligible?, to: :role

  # Invalidate production dashboard cache when vacancy changes
  after_commit :invalidate_dashboard_cache

  # Send notification to team when vacancy is created
  after_commit :notify_team_of_creation, on: :create

  def fill!(person, by: nil)
    transaction do
      # Get all shows in the linkage or just the primary show
      if show.linked?
        shows_to_update = show.event_linkage.shows.to_a
      else
        shows_to_update = [ show ]
      end

      shows_to_update.each do |affected_show|
        # Remove the old cast assignment for the entity who vacated (Person or Group)
        if vacated_by.present?
          affected_show.show_person_role_assignments
              .where(role_id: role_id, assignable_type: vacated_by_type, assignable_id: vacated_by_id)
              .destroy_all
        end

        # Create a new cast assignment for the person filling the vacancy
        affected_show.show_person_role_assignments.create!(
          role: role,
          assignable: person
        )

        # Unmark the show as finalized since the cast changed
        affected_show.update!(casting_finalized_at: nil)
      end

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
