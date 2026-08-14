# frozen_string_literal: true

# Dismiss/restore state for the intro guides rendered via shared/_intro_guide.
# State lives per-user in users.dismissed_guides (jsonb). Lives at the root
# (not under Manage::) because guides appear on both the manage side and the
# talent dashboard, and talent users may have no organization at all.
class GuidesController < ApplicationController
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
    talent_welcome
    profile_intro
    profile_checklist
  ].freeze

  def dismiss
    return head :unprocessable_entity unless GUIDE_KEYS.include?(params[:key])

    Current.user.dismiss_guide!(params[:key])
    redirect_back fallback_location: root_path
  end

  def restore
    return head :unprocessable_entity unless GUIDE_KEYS.include?(params[:key])

    Current.user.activate_guide!(params[:key])
    redirect_back fallback_location: root_path
  end
end
