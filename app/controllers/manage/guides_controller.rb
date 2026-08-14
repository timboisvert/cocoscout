# frozen_string_literal: true

module Manage
  # Dismiss/restore state for the intro guides rendered via shared/_intro_guide.
  # State lives per-user in users.dismissed_guides (jsonb).
  class GuidesController < Manage::ManageController
    # Only keys we actually render — keeps the jsonb from growing arbitrarily.
    GUIDE_KEYS = %w[
      production_next_steps
      casting_intro
      auditions_intro
      documents_intro
      courses_intro
      shows_intro
      contacts_intro
      messages_intro
      signups_intro
    ].freeze

    def dismiss
      return head :unprocessable_entity unless GUIDE_KEYS.include?(params[:key])

      Current.user.dismiss_guide!(params[:key])
      redirect_back fallback_location: manage_path
    end

    def restore
      return head :unprocessable_entity unless GUIDE_KEYS.include?(params[:key])

      Current.user.activate_guide!(params[:key])
      redirect_back fallback_location: manage_path
    end
  end
end
