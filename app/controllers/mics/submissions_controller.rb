# frozen_string_literal: true

# A signed-in user submits a new mic anywhere in the U.S. Lands with
# `pending: true` so it's invisible until a superadmin or hub editor
# approves it.
module Mics
  class SubmissionsController < AuthedBaseController
    def new
      @mic   = Mic.new
      @venue = Venue.new
    end

    def create
      ActiveRecord::Base.transaction do
        @venue = Venue.find_or_initialize_by(
          name: venue_params[:name],
          city: venue_params[:city],
          state: venue_params[:state]
        )
        @venue.assign_attributes(venue_params)
        @venue.save!

        @mic = Mic.new(mic_params)
        @mic.venue   = @venue
        @mic.pending = true
        @mic.save!

        @mic.mic_edits.create!(
          editor_user_id: current_user&.id,
          source: MicEdit.sources[:suggestion],
          field: "submission",
          new_value: "created",
          note: "Submitted via /mics/submit"
        )
      end

      redirect_to mics_detail_path(@mic.slug), notice: "Thanks! Your submission is pending review."
    rescue ActiveRecord::RecordInvalid => e
      flash.now[:alert] = e.message
      render :new, status: :unprocessable_content
    end

    private

    def venue_params
      params.require(:venue).permit(:name, :address1, :address2, :neighborhood, :city, :state, :postal_code, :country, :venue_type, :timezone)
    end

    def mic_params
      params.require(:mic).permit(:name, :format, :day_of_week, :starts_local_time, :signup_method, :bucket_draw, :signup_url, :signup_opens_at_text, :blurb, :spot_length_minutes, :signup_cap, :cost, :drink_minimum_amount_cents, :cover_amount_cents, :min_age, :host_summary)
    end
  end
end
