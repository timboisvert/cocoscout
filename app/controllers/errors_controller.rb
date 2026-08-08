# frozen_string_literal: true

class ErrorsController < ApplicationController
  skip_before_action :verify_authenticity_token
  allow_unauthenticated_access
  layout "error"

  def not_found
    render_error 404,
                 "Page not found",
                 "The page you're looking for doesn't exist or has been moved."
  end

  def unprocessable
    render_error 422,
                 "Something went wrong",
                 "The request couldn't be processed. This might happen if a form submission was invalid or a security check failed."
  end

  def internal_error
    @sentry_event_id = Sentry.last_event_id if defined?(Sentry)
    render_error 500,
                 "Something went wrong",
                 "We encountered an unexpected error. Our team has been notified and is looking into it."
  end

  private

  # production.rb sets `config.exceptions_app = self.routes`, so an unmatched
  # path is re-dispatched here with the ORIGINAL request's format still
  # attached. We only ship .html.erb templates, so anything asking for a
  # non-HTML path — /api_keys.json, /.gitlab-ci.yml, /.well-known/security.txt —
  # raised ActionView::MissingTemplate and came back as a 500 instead of a 404.
  # Scanners hammer those paths constantly, which is what tripped the ALB
  # target-5xx alarm. Answer in whatever format was asked for.
  def render_error(status, title, message)
    @status_code = status
    @title = title
    @message = message

    respond_to do |format|
      format.html { render action_name, status: status }
      format.json { render json: { status: status, error: title, message: message }, status: status }
      format.any  { render plain: "#{status} #{title}", status: status, content_type: "text/plain" }
    end
  end
end
