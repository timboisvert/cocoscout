# frozen_string_literal: true

# Tiny read-only JSON API. Honest payload shape, no sugar.
module Mics
  class ApiController < BaseController
    def index
      mics = Mic.active.includes(:venue).order(:name).limit(200)
      render json: { mics: mics.map { |m| as_json(m) } }
    end

    def by_city
      city, state = city_state_from_slug(params[:city_slug])
      mics = Mic.in_city(city, state).active.includes(:venue).order(:name) if city && state
      render json: { city: city, state: state, mics: (mics || []).map { |m| as_json(m) } }
    end

    def show_mic
      mic = Mic.includes(:venue).find_by!(slug: params[:slug].to_s.downcase)
      render json: as_json(mic, full: true)
    rescue ActiveRecord::RecordNotFound
      render json: { error: "not_found" }, status: :not_found
    end

    private

    def as_json(mic, full: false)
      base = {
        slug: mic.slug,
        name: mic.name,
        format: mic.format,
        day_of_week: mic.day_of_week,
        starts_local_time: mic.starts_local_time&.strftime("%H:%M"),
        signup_method: mic.signup_method,
        cost: mic.cost,
        venue: {
          name: mic.venue.name,
          city: mic.venue.city,
          state: mic.venue.state,
          neighborhood: mic.venue.neighborhood,
          lat: mic.venue.lat,
          lng: mic.venue.lng
        },
        url: mics_detail_url(mic.slug)
      }
      if full
        base.merge!(
          blurb: mic.blurb,
          signup_url: mic.signup_url,
          signup_opens_at_text: mic.signup_opens_at_text,
          spot_length_minutes: mic.spot_length_minutes,
          powered_by_cocoscout: mic.powered_by_cocoscout?,
          next_occurrences: mic.next_occurrences(limit: 6).map { |o|
            { starts_at: o[:starts_at].iso8601, mic_status: o[:mic_status] }
          }
        )
      end
      base
    end
  end
end
