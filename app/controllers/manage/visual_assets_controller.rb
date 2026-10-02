# frozen_string_literal: true

module Manage
  class VisualAssetsController < Manage::ManageController
    before_action :set_production
    before_action :check_production_access
    before_action :set_poster, only: %i[edit_poster update_poster destroy_poster set_primary_poster]
    before_action :ensure_user_is_manager, except: [ :index ]

    def index
      redirect_to edit_manage_production_path(@production, tab: 1)
    end





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

    private

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
