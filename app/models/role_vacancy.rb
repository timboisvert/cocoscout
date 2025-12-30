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

  enum :status, {
    open: "open",
    finding_replacement: "finding_replacement",
    not_filling: "not_filling",
    filled: "filled",
    cancelled: "cancelled"
  }

  # Scopes for active (still in progress) vs closed vacancies
  scope :active, -> { where(status: %w[open finding_replacement]) }
  scope :closed, -> { where(status: %w[not_filling filled cancelled]) }
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

  def mark_not_filling!(by: nil)
    update!(
      status: :not_filling,
      closed_at: Time.current,
      closed_by: by
    )
  end

  def mark_finding_replacement!
    update!(status: :finding_replacement) if open?
  end

  # Reclaim the vacancy - person who created it can now make it after all
  def reclaim!(by: nil)
    # Can reclaim if not already filled or cancelled
    # This includes: open, finding_replacement, and not_filling statuses
    return false if filled? || cancelled?

    transaction do
      # For linked shows, the assignment was kept throughout - nothing to restore
      # For non-linked shows, the assignment was removed and needs to be recreated
      unless show.linked?
        # Restore the assignment if it was a Person or Group
        if vacated_by.present?
          show.show_person_role_assignments.find_or_create_by!(
            role: role,
            assignable: vacated_by
          )
        end
      end

      # Note: For linked shows (affected_shows), we do NOT create assignments here
      # because the person was never removed from the cast. Each show has its own
      # role records, so we can't use this vacancy's role_id on other shows anyway.

      # Cancel the vacancy
      update!(
        status: :cancelled,
        closed_at: Time.current,
        closed_by: by
      )
    end

    # Notify team that the vacancy was reclaimed
    VacancyNotificationJob.perform_later(id, "reclaimed")
    true
  end

  def can_invite?(person)
    active? && !invitations.exists?(person: person)
  end

  # Check if vacancy is still active (in progress)
  def active?
    open? || finding_replacement?
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
