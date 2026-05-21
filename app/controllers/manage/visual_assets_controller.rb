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

    # Take a poster that's attached to a single Show and turn it into a
    # production-level Poster. The new Poster reuses the same blob (no
    # re-upload) and is marked primary. The show's own attachment is detached
    # so the show falls back to the new production poster — keeping a
    # single source of truth instead of two parallel images.
    def promote_show_poster
      show = @production.shows.find(params[:show_id])
      unless show.poster.attached?
        redirect_to edit_manage_production_path(@production, anchor: "tab-1"), alert: "That show doesn't have a poster to promote." and return
      end

      blob = show.poster.blob
      poster = @production.posters.new(
        name: show.display_name.presence || show.date_and_time.strftime("%b %-d, %Y"),
        is_primary: true
      )
      poster.image.attach(blob)

      if poster.save
        # Detach the show's own poster so it falls back to the new production
        # poster (same image, same display). Avoids carrying parallel state.
        show.poster.detach
        redirect_to edit_manage_production_path(@production, anchor: "tab-1"), notice: "Promoted to production poster."
      else
        redirect_to edit_manage_production_path(@production, anchor: "tab-1"), alert: poster.errors.full_messages.to_sentence.presence || "Could not promote poster."
      end
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

    def logo_params
      params.require(:production).permit(:logo)
    end
  end
end
