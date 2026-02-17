# frozen_string_literal: true

class ErrorsController < ApplicationController
  skip_before_action :verify_authenticity_token
  allow_unauthenticated_access
  layout "error"

  def not_found
    @status_code = 404
    @title = "Page not found"
    @message = "The page you're looking for doesn't exist or has been moved."
    render status: 404
  end

  def unprocessable
    @status_code = 422
    @title = "Something went wrong"
    @message = "The request couldn't be processed. This might happen if a form submission was invalid or a security check failed."
    render status: 422
  end

  def internal_error
    @status_code = 500
    @title = "Something went wrong"
    @message = "We encountered an unexpected error. Our team has been notified and is looking into it."
    @sentry_event_id = Sentry.last_event_id if defined?(Sentry)
    render status: 500
  end
end
