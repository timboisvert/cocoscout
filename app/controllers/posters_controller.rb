class PostersController < ApplicationController
  before_action :set_production
  before_action :set_poster, only: [ :edit, :update, :destroy ]

  def new
    @poster = @production.posters.new
  end

  def create
    @poster = @production.posters.new(poster_params)
    if @poster.save
      redirect_to @production, notice: "Poster was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @poster.update(poster_params)
      redirect_to @production, notice: "Poster was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @poster.destroy
    redirect_to @production, notice: "Poster was successfully deleted."
  end

  private
    def set_production
      @production = Production.find(params[:production_id])
    end

    def set_poster
      @poster = @production.posters.find(params[:id])
    end

    def poster_params
      params.require(:poster).permit(:name, :image)
    end
end
