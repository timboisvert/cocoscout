# frozen_string_literal: true

require "rails_helper"

# Production sets `config.exceptions_app = self.routes`, so an unmatched path is
# re-dispatched to ErrorsController with the ORIGINAL request's format still
# attached. A scanner asking for /api_keys.json therefore reached #not_found in
# JSON format, found only not_found.html.erb, raised MissingTemplate, and came
# back as a plain-text 500 — tripping the ALB target-5xx alarm.
RSpec.describe "Error pages", type: :request do
  # Mirror production's wiring: show_exceptions on, and unmatched paths
  # re-dispatched through the routes (config.exceptions_app = self.routes).
  around do |example|
    config = Rails.application.env_config
    original_show = config["action_dispatch.show_exceptions"]
    original_app  = config["action_dispatch.exception_app"]
    config["action_dispatch.show_exceptions"] = :all
    config["action_dispatch.exception_app"]  = Rails.application.routes
    example.run
    config["action_dispatch.show_exceptions"] = original_show
    config["action_dispatch.exception_app"]  = original_app
  end

  describe "unmatched paths" do
    it "returns 404 for an unknown HTML path" do
      get "/this-path-does-not-exist"
      expect(response).to have_http_status(:not_found)
    end

    # These are the exact paths the credential scanner hit on 2026-08-08.
    %w[
      /api_keys.json
      /aliyun_config.json
      /config/aliyun.json
      /.aliyun/config.json
      /swagger/v1/swagger.json
      /.well-known/assetlinks.json
    ].each do |path|
      it "returns 404, not 500, for #{path}" do
        get path
        expect(response).to have_http_status(:not_found)
      end
    end

    it "returns 404, not 500, for a non-HTML extension like .yml" do
      get "/.gitlab-ci.yml"
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404, not 500, for a .txt path" do
      get "/.well-known/security.txt"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "the error endpoints themselves" do
    it "renders 404 as JSON when JSON is asked for" do
      get "/404", headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:not_found)
      expect(response.content_type).to include("application/json")
      expect(response.parsed_body["status"]).to eq(404)
    end

    it "renders 422 as JSON when JSON is asked for" do
      get "/422", headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(422)
    end

    it "renders 500 as JSON when JSON is asked for" do
      get "/500", headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:internal_server_error)
    end

    it "falls back to plain text for a format with no template" do
      get "/404", headers: { "Accept" => "text/csv" }
      expect(response).to have_http_status(:not_found)
      expect(response.content_type).to include("text/plain")
    end

    it "does not raise on a junk Accept header" do
      get "/404", headers: { "Accept" => "application/x-nonsense" }
      expect(response.status).to eq(404)
    end

    it "still renders the HTML 404 page" do
      get "/404"
      expect(response).to have_http_status(:not_found)
      expect(response.content_type).to include("text/html")
      expect(response.body).to include("Page not found")
    end

    it "still renders the HTML 500 page" do
      get "/500"
      expect(response).to have_http_status(:internal_server_error)
      expect(response.content_type).to include("text/html")
    end
  end
end
