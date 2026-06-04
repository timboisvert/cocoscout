# frozen_string_literal: true

# Producer-facing wrapper around `Mics::MigrationService`. Presents the
# plan, lets the producer pick org + production, and runs the migration.
module Mics
  class MigrateController < AuthedBaseController
    before_action :load_mic_and_authorize

    def show
      @already_migrated = @mic.production_id.present?

      @organizations = Mics::MigrationService.organizations_for(current_user)
      @selected_org_id =
        if params[:organization_id].present?
          params[:organization_id].to_i
        else
          @organizations.first&.id
        end
      @selected_org = @organizations.detect { |o| o.id == @selected_org_id }

      @productions_in_org = @selected_org ? @selected_org.productions.order(:name) : []
      @suggested_production_name = @mic.name
      @default_org_name = "#{current_user.email_address.split("@").first.titleize} Productions"

      @show_count_preview = @mic.next_occurrences(limit: 200)
                                 .count { |o| o[:starts_at] <= 6.months.from_now }
      @first_occurrences = @mic.next_occurrences(limit: 5)
    end

    def create
      raise "Already migrated" if @mic.production_id
      result = Mics::MigrationService.new(
        mic: @mic,
        user: current_user,
        organization_id: params[:organization_id].presence,
        new_organization_name: params[:new_organization_name].presence,
        production_id: params[:production_id].presence,
        production_name: params[:production_name].presence,
        signup_form_defaults: {
          opens_days_before:     params[:signup_opens_days_before],
          slot_count:            params[:slot_count],
          slot_interval_minutes: params[:slot_interval_minutes],
          instruction_text:      params[:instruction_text]
        }
      ).call

      # Drop the producer straight into the sign-up form editor — that's
      # where the rest of the migration work happens (instructions, custom
      # questions, slot/cap, open/close timing, reminders, etc.). Falls
      # back to the production page if for some reason the form isn't
      # there.
      target = if result.sign_up_form
        edit_signups_form_path(result.production, result.sign_up_form)
      else
        manage_production_path(result.production)
      end

      redirect_to target,
                  notice: "Migrated #{@mic.name} — #{result.shows.size} open-mic dates added. Now customize the sign-up form below — performers won't see it until you're happy with it."
    rescue => e
      redirect_to mics_owner_migrate_path(@mic.slug), alert: "Migration failed: #{e.message}"
    end

    private

    def load_mic_and_authorize
      @mic = Mic.find_by!(slug: params[:slug].to_s.downcase)
      head :forbidden unless authorized?
    rescue ActiveRecord::RecordNotFound
      render plain: "Not found", status: :not_found
    end

    def authorized?
      return false unless current_user
      return true if current_user.respond_to?(:superadmin?) && current_user.superadmin?
      @mic.mic_owners.where(user_id: current_user.id, role: MicOwner.roles[:owner]).exists?
    end
  end
end
