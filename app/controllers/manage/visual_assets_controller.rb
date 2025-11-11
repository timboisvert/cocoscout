class Manage::VisualAssetsController < Manage::ManageController
  before_action :set_production
  before_action :check_production_access
  before_action :set_poster, only: [ :edit_poster, :update_poster, :destroy_poster ]
  before_action :ensure_user_is_manager, except: [ :index ]

  def index
  end

  def new_logo
  end

  def create_logo
    if @production.update(logo_params)
      redirect_to [ :manage, @production, :visual_assets ], notice: "Logo was successfully uploaded"
    else
      render :new_logo, status: :unprocessable_entity
    end
  end

  def edit_logo
  end

  def update_logo
    if @production.update(logo_params)
      redirect_to [ :manage, @production, :visual_assets ], notice: "Logo was successfully updated"
    else
      render :edit_logo, status: :unprocessable_entity
    end
  end

  def new_poster
    @poster = @production.posters.new
  end

  def create_poster
    @poster = @production.posters.new(poster_params)
    if @poster.save
      redirect_to [ :manage, @production, :visual_assets ], notice: "Poster was successfully created"
    else
      render :new_poster, status: :unprocessable_entity
    end
  end

  def edit_poster
  end

  def update_poster
    if @poster.update(poster_params)
      redirect_to [ :manage, @production, :visual_assets ], notice: "Poster was successfully updated"
    else
      render :edit_poster, status: :unprocessable_entity
    end
  end

  def destroy_poster
    @poster.destroy
    redirect_to [ :manage, @production, :visual_assets ], notice: "Poster was successfully deleted"
  end

  private
    def set_production
      @production = Current.production_company.productions.find(params[:production_id])
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
