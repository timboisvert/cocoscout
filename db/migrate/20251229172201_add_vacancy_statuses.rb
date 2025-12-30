class AddVacancyStatuses < ActiveRecord::Migration[8.1]
  def change
    # No schema changes needed - status is already a string column.
    # This migration documents the new vacancy statuses:
    # - open: Initial state when vacancy is created
    # - finding_replacement: Invitations have been sent out to find a replacement
    # - not_filling: Producer decided not to fill the role (close without replacing)
    # - filled: Someone claimed or was assigned to the role
    # - cancelled: Vacancy was manually cancelled and is no longer relevant
    #
    # Migration of existing data:
    # - "cancelled" vacancies that were "close without replacing" are now "not_filling"
    #   but we'll keep existing cancelled as-is since we can't distinguish them
  end
end
