# frozen_string_literal: true

module My
  # The same page as a visual asset request's link, for someone on the
  # contract who has an account (Tim, 2026-11-19: "the account taking over
  # the link"): signed in, from My Contracts, with no link to keep. It is
  # there while the production's request is open, and what they add carries
  # their name.
  class ContractAssetsController < ApplicationController
    include AssetUploading

    before_action :require_authentication
    before_action :set_contract

    def show
      @show_my_sidebar = true
      @assets = asset_assets
      @counts = @assets.counts
    end

    def upload
      perform_asset_upload
    end

    def save_text
      perform_asset_text_save
    end

    private

    def set_contract
      @contract = Contract.visible_to(Current.user).find(params[:id])
      @production = @contract.production
      @request = @production && AssetRequest.current_for(@production)
      return if @request&.open?

      message = "#{@contract.organization.name} isn't requesting images or details for this show right now."
      if request.format.json? || request.xhr? || !request.get?
        render json: { ok: false, message: message }, status: :gone
      else
        redirect_to my_contracts_path, alert: message
      end
    end

    def asset_production = @production
    def asset_uploader_user = Current.user
    def asset_uploader_name = Current.user.person&.name
    def asset_request_for_log = @request
    def asset_may_replace?(item) = @request.allow_replace? || asset_added_through?(item, @request)
    def asset_after_change = @request.note_activity!

    def asset_page_locals
      { organization: @production.organization, request: @request,
        upload_address: my_contract_assets_upload_path(@contract),
        text_address: ->(spec) { my_contract_assets_text_path(@contract, spec_id: spec.id) },
        can_replace: ->(item) { asset_may_replace?(item) } }
    end
    helper_method :asset_page_locals
  end
end
