# frozen_string_literal: true

# Producer-facing wrapper around `Mics::MigrationService`. Confirms
# intent on GET, runs the migration on POST.
module Mics
  class MigrateController < AuthedBaseController
    before_action :load_mic_and_authorize

    def show
      @already_migrated = @mic.production_id.present?
    end

    def create
      raise "Already migrated" if @mic.production_id
      result = Mics::MigrationService.new(mic: @mic, user: current_user).call
      redirect_to mics_producer_mic_path(@mic.slug),
                  notice: "Migrated — created #{result.shows.size} shows + sign-up form."
    rescue => e
      redirect_to mics_producer_migrate_path(@mic.slug), alert: "Migration failed: #{e.message}"
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
      @mic.mic_producers.where(user_id: current_user.id, role: MicProducer.roles[:producer]).exists?
    end
  end
end
