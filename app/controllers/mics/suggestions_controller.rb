# frozen_string_literal: true

# Edit suggestions on an existing Mic. Can be filed anonymously (with a
# valid email) or by a signed-in user.
module Mics
  class SuggestionsController < ApplicationController
    allow_unauthenticated_access only: %i[new create]
    before_action :suppress_app_chrome
    before_action :load_mic

    def new
      @suggestion = MicSuggestion.new
    end

    def create
      @suggestion = @mic.mic_suggestions.build(suggestion_params)
      @suggestion.submitter = Current.user
      @suggestion.status = :pending

      if @suggestion.save
        redirect_to mics_suggest_thanks_path(@mic.slug)
      else
        flash.now[:alert] = @suggestion.errors.full_messages.to_sentence
        render :new, status: :unprocessable_content
      end
    end

    def thanks
      # Dedicated confirmation page (vs. flash on the detail page that's
      # easy to miss).
    end

    private

    def suppress_app_chrome
      @show_my_sidebar = false
      @show_manage_sidebar = false
      @show_manage_header_only = false
      @show_group_sidebar = false
      @show_account_sidebar = false
    end

    def load_mic
      @mic = Mic.find_by!(slug: params[:slug].to_s.downcase)
    rescue ActiveRecord::RecordNotFound
      render plain: "Not found", status: :not_found
    end

    def suggestion_params
      params.require(:mic_suggestion).permit(:submitter_email, :note, payload: {})
    end
  end
end
