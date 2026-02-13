# frozen_string_literal: true

class ShowTransferService
  class << self
    def transfer(show, target_production)
      ActiveRecord::Base.transaction do
        old_production = show.production

        # Update the production reference on the show
        show.update!(production_id: target_production.id)

        # === SIGN-UP FORMS ===
        # Transfer sign-up forms that belong directly to this show
        SignUpForm.where(show_id: show.id).update_all(production_id: target_production.id)

        # Transfer sign-up forms that have instances linked to this show
        SignUpFormInstance.where(show_id: show.id).includes(:sign_up_form).each do |instance|
          if instance.sign_up_form.present? && instance.sign_up_form.production_id == old_production.id
            instance.sign_up_form.update!(production_id: target_production.id)
          end
        end

        # Transfer sign-up forms linked via sign_up_form_shows join table
        SignUpFormShow.where(show_id: show.id).includes(:sign_up_form).each do |form_show|
          if form_show.sign_up_form.production_id == old_production.id
            form_show.sign_up_form.update!(production_id: target_production.id)
          end
        end

        # === CUSTOM ROLES ===
        # Show-specific roles need their production_id updated
        Role.where(show_id: show.id).update_all(production_id: target_production.id)

        # === MESSAGES ===
        # Update messages scoped to this show
        Message.where(show_id: show.id, production_id: old_production.id)
               .update_all(production_id: target_production.id)

        # === SHOW PAYOUT ===
        if show.show_payout.present?
          # Clear payout scheme if it was from the old production
          if show.show_payout.payout_scheme&.production_id == old_production.id
            show.show_payout.update!(payout_scheme_id: nil)
          end
        end

        # === RECURRENCE GROUP ===
        # Detach from recurrence group when transferring single show
        if show.recurrence_group_id.present?
          show.update!(recurrence_group_id: nil)
        end

        # === EVENT LINKAGES ===
        # Detach from event linkage when transferring single show
        if show.event_linkage.present?
          linkage = show.event_linkage
          remaining_in_linkage = linkage.shows.where.not(id: show.id).count

          if remaining_in_linkage.zero?
            linkage.destroy
          else
            show.update!(event_linkage_id: nil)
          end
        end

        { success: true }
      end
    rescue ActiveRecord::RecordInvalid => e
      { success: false, error: e.message }
    rescue StandardError => e
      Rails.logger.error "ShowTransferService error: #{e.message}"
      Rails.logger.error e.backtrace.first(10).join("\n")
      { success: false, error: "An unexpected error occurred" }
    end
  end
end
