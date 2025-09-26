class My::ProfileController < ApplicationController
  def index
  end

  def edit
    @person = Current.user.person
  end
end
