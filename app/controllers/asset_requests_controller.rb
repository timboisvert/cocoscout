# frozen_string_literal: true

# The no-login page where someone outside adds a production's images and
# words (AssetRequest; Tim, 2026-11-19). Anyone holding the link can use it,
# until the production's last date has passed or the organization turns it
# off. Each file is checked against its specification as it arrives, and a
# signed-out visitor is offered a free CocoScout account at the foot.
class AssetRequestsController < ApplicationController
  include AssetUploading

  allow_unauthenticated_access
  before_action :resume_session
  before_action :set_request

  layout "storefront"

  def show
    @storefront_organization = @production.organization
    @storefront_sold_line = "Requested by #{@production.organization.name}"
    @storefront_brand = "CocoScout"
    return render(:closed, status: :gone) unless @request.open?

    session[:return_to] = asset_request_path(token: @request.token) unless authenticated?
    @assets = asset_assets
    @counts = @assets.counts
  end

  def upload
    return render(json: { ok: false, message: closed_message }, status: :gone) unless @request.open?

    perform_asset_upload
  end

  def save_text
    return render(json: { ok: false, message: closed_message }, status: :gone) unless @request.open?

    perform_asset_text_save
  end

  private

  def set_request
    @request = AssetRequest.find_by(token: params[:token].to_s)
    unless @request
      @storefront_brand = "CocoScout"
      return render(:not_found, status: :not_found)
    end

    @production = @request.production
  end

  def closed_message
    "This link has been turned off, so it no longer takes uploads. Request a new link from #{@production.organization.name}."
  end

  def asset_production = @production
  def asset_uploader_user = Current.user
  def asset_uploader_name = Current.user&.person&.name || asset_typed_name
  def asset_request_for_log = @request
  def asset_may_replace?(item) = @request.allow_replace? || asset_added_through?(item, @request)
  def asset_after_change = @request.note_activity!

  def asset_page_locals
    { organization: @production.organization, request: @request,
      upload_address: asset_request_upload_path(token: @request.token),
      text_address: ->(spec) { asset_request_text_path(token: @request.token, spec_id: spec.id) },
      can_replace: ->(item) { asset_may_replace?(item) } }
  end
  helper_method :asset_page_locals
end
