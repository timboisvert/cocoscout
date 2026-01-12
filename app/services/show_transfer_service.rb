# frozen_string_literal: true

class ShowTransferService
  class << self
    def transfer(show, target_production)
      ActiveRecord::Base.transaction do
        old_production = show.production

        # Update the production reference
        show.update!(production_id: target_production.id)

        # Handle show roles - if using custom roles, they need to move too
        if show.use_custom_roles
          # Custom show roles stay with the show, nothing to do
        else
          # Show was using production roles - check if same roles exist in target
          # For now, keep assignments but they may need reconfiguration
        end

        # Move any show financials (they belong to the show, not production)
        # Already handled by association

        # Update show payout references if they exist
        if show.show_payout.present?
          # The show_payout belongs_to :show, so it moves automatically
          # But we may need to update payout_scheme if it was production-specific
          if show.show_payout.payout_scheme&.production_id == old_production.id
            # Clear the scheme - user will need to select a new one
            show.show_payout.update!(payout_scheme_id: nil)
          end
        end

        # Handle recurring group if this is part of one
        if show.recurrence_group_id.present?
          recurrence_group = show.recurrence_group
          remaining_in_group = recurrence_group.where.not(id: show.id).count

          if remaining_in_group.zero?
            # This was the last show in the group, remove the group reference
            show.update!(recurrence_group_id: nil)
          end
          # Otherwise, the show is now detached from its recurrence group
          show.update!(recurrence_group_id: nil)
        end

        # Handle event linkages
        if show.event_linkage.present?
          linkage = show.event_linkage
          remaining_in_linkage = linkage.shows.where.not(id: show.id).count

          if remaining_in_linkage.zero?
            # This was the only show in the linkage, destroy it
            linkage.destroy
          else
            # Remove this show from the linkage
            linkage.shows.delete(show)
          end
        end

        { success: true }
      end
    rescue ActiveRecord::RecordInvalid => e
      { success: false, error: e.message }
    rescue StandardError => e
      Rails.logger.error "ShowTransferService error: #{e.message}"
      { success: false, error: "An unexpected error occurred" }
    end
  end
end
