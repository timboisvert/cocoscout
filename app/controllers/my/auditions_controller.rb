class My::AuditionsController < ApplicationController
  # GET /auditions
  def index
    @auditions = Audition.all
  end
end
