class My::ProfileController < ApplicationController
  def index
  end

  def edit
    @person = Current.user.person
  end

  def update
    @person = Current.user.person
    if @person.update(person_params)
      redirect_to my_profile_path, notice: "Profile was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private
    def person_params
      params.require(:person).permit(
        :name, :email, :pronouns, :resume, :headshot,
        socials_attributes: [ :id, :platform, :handle, :_destroy ]
      )
    end
end
