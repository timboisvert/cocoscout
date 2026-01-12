# frozen_string_literal: true

class SignUpFormTransferService
  class << self
    def transfer(sign_up_form, target_production)
      ActiveRecord::Base.transaction do
        # Clear event-specific associations that won't be valid in new production
        clear_event_associations(sign_up_form)

        # Update the production reference
        sign_up_form.update!(
          production_id: target_production.id,
          show_id: nil # Clear single event reference
        )

        # Regenerate URL slug if it conflicts
        ensure_unique_slug(sign_up_form, target_production)
      end
    end

    private

    def clear_event_associations(sign_up_form)
      # Clear sign_up_form_shows (manual event selections)
      sign_up_form.sign_up_form_shows.destroy_all

      # Clear sign_up_form_instances (they reference shows from old production)
      sign_up_form.sign_up_form_instances.destroy_all

      # Clear any direct sign_up_slots that reference the old form
      # (these will be regenerated when instances are created)
      sign_up_form.sign_up_slots.destroy_all

      # Reset the form to need reconfiguration
      if sign_up_form.single_event?
        # Convert to shared_pool since there's no show to link to
        sign_up_form.update!(scope: "shared_pool")
      end
    end

    def ensure_unique_slug(sign_up_form, target_production)
      original_slug = sign_up_form.url_slug
      return unless original_slug.present?

      # Check if slug already exists in target production
      existing = target_production.sign_up_forms
                                  .where.not(id: sign_up_form.id)
                                  .exists?(url_slug: original_slug)

      if existing
        # Generate a new unique slug
        base_slug = original_slug.gsub(/-\d+$/, "") # Remove any existing numeric suffix
        counter = 1
        new_slug = "#{base_slug}-#{counter}"

        while target_production.sign_up_forms.where.not(id: sign_up_form.id).exists?(url_slug: new_slug)
          counter += 1
          new_slug = "#{base_slug}-#{counter}"
        end

        sign_up_form.update!(url_slug: new_slug)
      end
    end
  end
end
