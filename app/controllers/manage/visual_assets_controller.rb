# frozen_string_literal: true

module Manage
  class VisualAssetsController < Manage::ManageController
    include AssetUploading

    before_action :set_production
    before_action :check_production_access
    before_action :set_poster, only: %i[edit_poster update_poster destroy_poster set_primary_poster]
    before_action :ensure_user_is_manager

    def new_poster
      redirect_to edit_manage_production_path(@production, tab: 1)
    end

    def create_poster
      @poster = @production.posters.new(poster_params)
      if @poster.save
        redirect_to edit_manage_production_path(@production, tab: 1), notice: "Poster was successfully created"
      else
        redirect_to edit_manage_production_path(@production, tab: 1), alert: "Could not create poster"
      end
    end

    def edit_poster
      redirect_to edit_manage_production_path(@production, tab: 1)
    end

    def update_poster
      if @poster.update(poster_params)
        redirect_to edit_manage_production_path(@production, tab: 1), notice: "Poster was successfully updated"
      else
        redirect_to edit_manage_production_path(@production, tab: 1), alert: "Could not update poster"
      end
    end

    def destroy_poster
      @poster.destroy
      redirect_to edit_manage_production_path(@production, tab: 1), notice: "Poster was successfully deleted"
    end

    def set_primary_poster
      @poster.update!(is_primary: true)
      redirect_to edit_manage_production_path(@production, tab: 1), notice: "Poster was set as primary"
    end


    # The production's wide image (16:9, HasWideImage): with the poster, one
    # of the two pictures every production has. Shows can use their own.
    def update_wide_image
      file = params.dig(:production, :wide_image)
      if file.blank?
        redirect_to edit_manage_production_path(@production, tab: 1), alert: "Choose a picture to upload." and return
      end

      if @production.update(wide_image: file)
        redirect_to edit_manage_production_path(@production, tab: 1), notice: "Wide image saved."
      else
        redirect_to edit_manage_production_path(@production, tab: 1), alert: @production.errors.full_messages_for(:wide_image).to_sentence
      end
    end

    def remove_wide_image
      @production.wide_image.purge_later if @production.wide_image.attached?
      redirect_to edit_manage_production_path(@production, tab: 1), notice: "Wide image removed."
    end


    # Any item on the organization's list (AssetSpec), held to its
    # specification (AssetCheck). Answers JSON; the tab reloads itself.
    def upload
      perform_asset_upload(cards: false)
    end

    # A written item. The Show description is edited on Basic Information,
    # where its formatting lives.
    def save_text
      spec = asset_spec_from_params("text")
      return redirect_to(tab_path, alert: "That item is no longer on the list.") unless spec

      asset_assets.store_text!(spec, params[:text], user: Current.user, name: asset_uploader_name)
      redirect_to tab_path, notice: "#{spec.name} saved."
    rescue ActiveRecord::RecordInvalid => e
      redirect_to tab_path, alert: e.record.errors.full_messages.to_sentence
    end

    # Takes away the file or words this production has for one of the
    # organization's own items. The Poster and the Wide image have their own.
    def remove_item
      spec = asset_assets.specs.find { |candidate| candidate.id == params[:spec_id].to_i }
      return redirect_to(tab_path, alert: "That item is no longer on the list.") unless spec && !spec.builtin?

      asset_assets.remove!(spec)
      redirect_to tab_path, notice: "#{spec.name} removed."
    end

    # A file of the production's own, any size, matching nothing on the list.
    def add_file
      asset = @production.production_assets.new(name: params[:name].to_s.strip.presence || params[:file].try(:original_filename),
                                                uploaded_by_user: Current.user, uploaded_by_name: asset_uploader_name,
                                                last_change: "added", changed_at: Time.current)
      asset.file.attach(params[:file]) if params[:file].present?
      if asset.save
        redirect_to tab_path, notice: "#{asset.name} added."
      else
        redirect_to tab_path, alert: asset.errors.full_messages.to_sentence
      end
    end

    def remove_file
      asset = @production.production_assets.additional.find(params[:id])
      asset.destroy!
      redirect_to tab_path, notice: "#{asset.name} removed."
    end

    # Request these: one link for the production (one stays open while it
    # works), emailed to whoever the manager picks. "Copy the link" makes it
    # without emailing anyone.
    def send_request
      request = AssetRequest.current_for(@production)
      request = nil if request && !request.open?
      request ||= @production.asset_requests.new(created_by: Current.user)

      emails = (Array(params[:recipients]) + params[:other_emails].to_s.split(/[,;\n]+/)).map { |email| email.to_s.strip.downcase }
                 .compact_blank.uniq
      bad = emails.reject { |email| email.match?(URI::MailTo::EMAIL_REGEXP) }
      if bad.any?
        words = bad.map { |email| %("#{email}") }.to_sentence
        return redirect_to(tab_path, alert: "#{words} #{bad.one? ? "isn't an email address" : "aren't email addresses"}. Separate addresses with commas.")
      end

      sending = params[:commit_action] != "copy"
      return redirect_to(tab_path, alert: "Choose someone to send the link to, or copy the link instead.") if sending && emails.empty?

      request.assign_attributes(subject: params[:subject].to_s.strip.presence || default_request_subject,
                                message: params[:message].to_s.strip.presence, allow_replace: params[:allow_replace] == "1",
                                recipients: (request.recipient_emails + emails).uniq)
      request.save!

      if sending
        AssetRequestMailing.deliver!(request, emails, sender: Current.user)
        request.update!(sent_at: Time.current)
        redirect_to tab_path, notice: "The request has been sent to #{emails.to_sentence}."
      else
        redirect_to tab_path, notice: "The link is ready. Copy it from the top of this page."
      end
    end

    def remind_request
      request = live_request
      return redirect_to(tab_path, alert: "There is no open request to send a reminder for.") unless request&.open?
      return redirect_to(tab_path, alert: "Nobody has been emailed this link yet.") if request.recipient_emails.empty?

      AssetRequestMailing.deliver!(request, request.recipient_emails, sender: Current.user, reminder: true)
      redirect_to tab_path, notice: "A reminder has been sent to #{request.recipient_emails.to_sentence}."
    end

    def turn_off_request
      request = live_request
      request&.turn_off!
      redirect_to tab_path, notice: "The link has been turned off. Nobody can add anything with it now."
    end

    # A new link ends the old one (a link forwarded where it shouldn't be).
    def new_link
      old = live_request
      fresh = @production.asset_requests.new(created_by: Current.user, recipients: old&.recipients || [],
                                             subject: old&.subject, message: old&.message, allow_replace: old ? old.allow_replace : true)
      AssetRequest.transaction do
        old&.turn_off!
        fresh.save!
      end
      redirect_to tab_path, notice: "There is a new link. The old one no longer works, so send this one with a reminder."
    end

    private

    def tab_path
      edit_manage_production_path(@production, tab: helpers.production_edit_tab(@production, :visual_assets))
    end

    def live_request = AssetRequest.current_for(@production)

    def default_request_subject = "Images and details we need for #{@production.name}"

    # AssetUploading: a manager adding on the tab is never notified about
    # their own changes, and may replace anything.
    def asset_production = @production
    def asset_uploader_user = Current.user
    def asset_uploader_name = Current.user&.person&.name
    def asset_request_for_log = nil
    def asset_may_replace?(_item) = true
    def asset_after_change; end
    def asset_page_locals = {}

    def set_production
      unless Current.organization
        redirect_to select_organization_path, alert: "Please select an organization first."
        return
      end
      @production = Current.organization.productions.find(params[:production_id])
      sync_current_production(@production)
    end

    def set_poster
      @poster = @production.posters.find(params[:id])
    end

    def poster_params
      params.require(:poster).permit(:name, :image)
    end
  end
end
