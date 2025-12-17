# frozen_string_literal: true

class CalendarFeedsController < ApplicationController
  allow_unauthenticated_access only: [ :show ]

  def show
    subscription = CalendarSubscription.find_by!(ical_token: params[:token])

    unless subscription.enabled?
      head :gone
      return
    end

    ical_service = CalendarSync::IcalService.new(subscription)
    ical_content = ical_service.generate_feed

    response.headers["Content-Type"] = "text/calendar; charset=utf-8"
    response.headers["Content-Disposition"] = "inline; filename=cocoscout-calendar.ics"
    render plain: ical_content
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end
end
