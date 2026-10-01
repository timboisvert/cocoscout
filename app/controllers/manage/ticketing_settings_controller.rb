# frozen_string_literal: true

module Manage
  # Ticketing settings, a routed-section page like Money and Contract settings:
  # the box office itself (its address, who pays fees, the pilot switch) and
  # tax on tickets. No branding in v1 — every org gets the same pages.
  class TicketingSettingsController < Manage::TicketingBaseController
    SECTIONS = %w[box_office tax].freeze
    SECTION_LABELS = { "box_office" => "Box office", "tax" => "Tax" }.freeze
    DEFAULT_SECTION = "box_office"

    before_action :set_section, only: %i[show]

    def show
      @tax = TicketTaxSetting.current(Current.organization) if @section == "tax"
    end

    def update
      attrs = params.require(:ticketing_profile)
                    .permit(:slug, :support_email, :default_fee_mode, :default_max_per_order, :enabled)
      # The pilot switch is a superadmin's call, even once managers can get here.
      attrs.delete(:enabled) unless Current.user.superadmin?

      if ticketing_profile.update(attrs)
        redirect_to section_path("box_office"), notice: "Box office settings saved."
      else
        @section = "box_office"
        flash.now[:alert] = ticketing_profile.errors.full_messages.to_sentence
        render :show, status: :unprocessable_entity
      end
    end

    def update_tax
      tax = params.fetch(:tax, {}).permit(:name, :percent, :mode)
      rule = TicketTaxSetting.save!(Current.organization, name: tax[:name], percent: tax[:percent], mode: tax[:mode])
      redirect_to section_path("tax"), notice: rule ? "Tax on tickets saved." : "Tickets now carry no tax."
    rescue ArgumentError, ActiveRecord::RecordInvalid => e
      redirect_to section_path("tax"), alert: e.message
    end

    private

    def sections
      SECTIONS.map { |key| { key: key, label: SECTION_LABELS.fetch(key), path: section_path(key) } }
    end
    helper_method :sections

    def section_path(key)
      manage_ticketing_settings_section_path(section: key)
    end

    def set_section
      @section = params[:section].presence || DEFAULT_SECTION
      redirect_to section_path(DEFAULT_SECTION) unless @section.in?(SECTIONS)
    end
  end
end
