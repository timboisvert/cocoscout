# frozen_string_literal: true

module Manage
  class VisualAssetsController < Manage::ManageController
    before_action :set_production
    before_action :check_production_access
    before_action :set_poster, only: %i[edit_poster update_poster destroy_poster set_primary_poster]
    before_action :ensure_user_is_manager, except: [ :index ]

    def index
      redirect_to edit_manage_production_path(@production, anchor: "tab-1")
    end

    def new_logo
      redirect_to edit_manage_production_path(@production, anchor: "tab-1")
    end

    def create_logo
      if @production.update(logo_params)
        redirect_to edit_manage_production_path(@production, anchor: "tab-1"), notice: "Logo was successfully uploaded"
      else
        redirect_to edit_manage_production_path(@production, anchor: "tab-1"), alert: "Could not upload logo"
      end
    end

    def edit_logo
      redirect_to edit_manage_production_path(@production, anchor: "tab-1")
    end

    def update_logo
      if @production.update(logo_params)
        redirect_to edit_manage_production_path(@production, anchor: "tab-1"), notice: "Logo was successfully updated"
      else
        redirect_to edit_manage_production_path(@production, anchor: "tab-1"), alert: "Could not update logo"
      end
    end

    def new_poster
      redirect_to edit_manage_production_path(@production, anchor: "tab-1")
    end

    def create_poster
      @poster = @production.posters.new(poster_params)
      if @poster.save
        redirect_to edit_manage_production_path(@production, anchor: "tab-1"), notice: "Poster was successfully created"
      else
        redirect_to edit_manage_production_path(@production, anchor: "tab-1"), alert: "Could not create poster"
      end
    end

    def edit_poster
      redirect_to edit_manage_production_path(@production, anchor: "tab-1")
    end

    def update_poster
      if @poster.update(poster_params)
        redirect_to edit_manage_production_path(@production, anchor: "tab-1"), notice: "Poster was successfully updated"
      else
        redirect_to edit_manage_production_path(@production, anchor: "tab-1"), alert: "Could not update poster"
      end
    end

    def destroy_poster
      @poster.destroy
      redirect_to edit_manage_production_path(@production, anchor: "tab-1"), notice: "Poster was successfully deleted"
    end

    def set_primary_poster
      @poster.update!(is_primary: true)
      redirect_to edit_manage_production_path(@production, anchor: "tab-1"), notice: "Poster was set as primary"
    end

    private

    def set_production
      @production = Current.organization.productions.find(params[:production_id])
    end

    def set_poster
      @poster = @production.posters.find(params[:id])
    end

    def poster_params
      params.require(:poster).permit(:name, :image)
    end

    def logo_params
      params.require(:production).permit(:logo)
    end
  end
end
