# frozen_string_literal: true

module Manage
  # The organization's visual asset specifications, edited on Organization
  # settings → Visual Assets (Tim, 2026-11-19): the images and written items
  # it expects every production to have, in the order people see them. The
  # list renders in organizations/sections/_visual_assets.
  class AssetSpecsController < Manage::ManageController
    before_action :ensure_user_can_manage_organization
    before_action :set_spec, only: %i[update destroy]

    def create
      kind = params.dig(:asset_spec, :kind) == "text" ? "text" : "image"
      spec = Current.organization.asset_specs.new(kind: kind, position: next_position, formats: kind == "image" ? %w[jpg png] : [])
      if save_spec(spec)
        redirect_to section_path, notice: "#{spec.name} added."
      else
        redirect_to section_path, alert: spec.errors.full_messages.to_sentence
      end
    end

    def update
      if save_spec(@spec)
        redirect_to section_path, notice: "#{@spec.name} saved."
      else
        redirect_to section_path, alert: @spec.errors.full_messages.to_sentence
      end
    end

    # Removing one keeps what productions already have (AssetSpec#archive!).
    # The built-ins can't be removed.
    def destroy
      if @spec.builtin?
        redirect_to section_path, alert: "#{@spec.name} is built in, so it can't be removed."
      else
        @spec.archive!
        redirect_to section_path, notice: "#{@spec.name} removed."
      end
    end

    # The drag-to-reorder list (role_order_controller posts role_ids).
    def reorder
      ids = Array(params[:role_ids] || params[:ids]).map(&:to_i)
      specs = Current.organization.asset_specs.active.where(id: ids).index_by(&:id)
      AssetSpec.transaction do
        ids.each_with_index { |id, index| specs[id]&.update_column(:position, index) }
      end
      head :ok
    end

    private

    def set_spec
      @spec = Current.organization.asset_specs.active.find(params[:id])
    end

    def section_path
      section_manage_organization_path(Current.organization, section: "visual_assets")
    end

    def next_position
      (Current.organization.asset_specs.maximum(:position) || -1) + 1
    end

    def ensure_user_can_manage_organization
      return if Current.organization&.manageable_by?(Current.user)

      redirect_to manage_path, alert: "Only the organization's managers can change its visual assets."
    end

    def save_spec(spec)
      attrs = params.require(:asset_spec).permit(:name, :used_for, :guidance, :required, :unit, :width, :height, :dpi,
                                                 :max_megabytes, :max_length, formats: [])
      spec.name = attrs[:name].to_s.strip if attrs.key?(:name)
      spec.used_for = attrs[:used_for].to_s.strip.presence
      spec.guidance = attrs[:guidance].to_s.strip.presence
      spec.required = attrs[:required] == "1" if attrs.key?(:required)

      if spec.image?
        assign_size(spec, attrs)
        spec.formats = Array(attrs[:formats]).compact_blank & AssetSpec::FORMATS.keys if attrs.key?(:formats) || spec.new_record?
        spec.max_megabytes = attrs[:max_megabytes].to_i if attrs[:max_megabytes].present?
      else
        spec.max_length = attrs[:max_length].presence&.to_i
      end
      spec.save
    end

    # The built-ins keep their shape: only the smallest width is asked for,
    # and the height follows (rounded so the shape is exact). Anything else
    # is pixels, or inches at a DPI for print.
    def assign_size(spec, attrs)
      if spec.builtin.in?(%w[poster wide])
        step, across, down = spec.builtin == "poster" ? [ 3, 3, 4 ] : [ 16, 16, 9 ]
        width = (attrs[:width].to_f / step).round * step
        width = step if width < step
        spec.width = width
        spec.height = width / across * down
      elsif attrs[:unit] == "inches"
        dpi = attrs[:dpi].to_i
        spec.dpi = dpi.positive? ? dpi : 300
        spec.width = (attrs[:width].to_f * spec.dpi).round
        spec.height = (attrs[:height].to_f * spec.dpi).round
      else
        spec.dpi = nil
        spec.width = attrs[:width].to_i
        spec.height = attrs[:height].to_i
      end
    end
  end
end
