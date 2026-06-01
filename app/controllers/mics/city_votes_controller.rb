# frozen_string_literal: true

module Mics
  class CityVotesController < BaseController
    def create
      vote = CityVote.new(
        city:  params[:city],
        state: params[:state],
        email: Current.user ? nil : params[:email].to_s.strip.presence,
        user_id: Current.user&.id
      )

      if vote.save
        redirect_back fallback_location: mics_home_path,
                      notice: "Thanks — we'll let you know when #{vote.city}, #{vote.state} goes live."
      else
        redirect_back fallback_location: mics_home_path,
                      alert: vote.errors.full_messages.to_sentence
      end
    end
  end
end
