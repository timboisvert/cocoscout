# frozen_string_literal: true

module Manage
  # Mailing list settings (a leaf): how emails look, what checkout asks, and
  # how much of this month's allowance is used.
  class MailingListSettingsController < ManageController
    SECTIONS = %w[look checkout allowance].freeze
    SECTION_LABELS = { "look" => "Email look", "checkout" => "Checkout", "allowance" => "Allowance" }.freeze

    def show
      @section = params[:section].presence_in(SECTIONS) || "look"
      @organization = Current.organization
      @profile = TicketingProfile.for(@organization)
      @allowance = FollowerEmailAllowance.new(@organization)
      @collecting_lists = @organization.mailing_lists.active.where(kind: "group").includes(:productions).order(:name).to_a
    end

    def update_look
      attrs = params.require(:organization).permit(:email_accent_color, :email_footer_line, :email_website_url, :email_instagram, :email_mailing_address)
      attrs[:email_accent_color] = nil unless Organization::EMAIL_ACCENTS.value?(attrs[:email_accent_color])
      Current.organization.update!(attrs)
      Current.organization.logo.attach(params[:organization][:logo]) if params.dig(:organization, :logo).present?
      redirect_to manage_mailing_list_settings_path(section: "look"), notice: "Saved."
    end

    def update_checkout
      profile = TicketingProfile.for(Current.organization)
      profile.update!(params.require(:ticketing_profile).permit(:follow_at_checkout, :follow_boxes_ticked, :follow_main_words))
      redirect_to manage_mailing_list_settings_path(section: "checkout"), notice: "Saved."
    end
  end
end
