class My::AuditionsController < ApplicationController
  def index
    @auditions = Audition.all
  end
end
