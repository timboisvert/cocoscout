# frozen_string_literal: true

# Individual mic detail page.
module Mics
  class DetailController < BaseController
    before_action :load_mic

    def show
      # Pull a few months ahead so the calendar view has something to
      # show. View toggles between "calendar" (default) and "list" via
      # a single query param; we don't refetch.
      @next_occurrences = @mic.next_occurrences(limit: 16)
      @signup_info = @mic.signup_info
      @upcoming_view = params[:view] == "list" ? "list" : "calendar"
    end

    private

    def load_mic
      @mic = Mic.find_by!(slug: params[:slug].to_s.downcase)
      # Pending submissions are admin-only. Superadmins, hub captains
      # for the venue's hub, and the people listed on the mic itself
      # may preview; everyone else gets a 404 so we don't leak a
      # not-yet-approved listing's URL.
      if @mic.pending && !previewable_by_admin?
        render plain: "Not found", status: :not_found
      end
    rescue ActiveRecord::RecordNotFound
      render plain: "Not found", status: :not_found
    end

    def previewable_by_admin?
      Current.user && @mic.manageable_by?(Current.user)
    end
  end
end
