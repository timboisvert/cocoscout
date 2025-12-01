class My::ShoutoutsController < ApplicationController
  before_action :require_authentication
  before_action :set_shoutee, only: [ :new, :create ]
  before_action :set_shoutout, only: [ :destroy ]

  def index
    @person = Current.user.person

    # Get received shoutouts for the current user's person
    @received_shoutouts = @person.received_shoutouts.newest_first

    # Get given shoutouts by the current user
    @given_shoutouts = @person.given_shoutouts.newest_first.includes(:shoutee)

    # Determine which tab to show
    @active_tab = params[:tab] || "received"
  end

  def new
    @shoutout = Shoutout.new(shoutee: @shoutee)
  end

  def create
    @shoutout = Shoutout.new(shoutout_params)
    @shoutout.author = Current.user.person
    @shoutout.shoutee = @shoutee

    if @shoutout.save
      redirect_to public_profile_shoutouts_path(@shoutee.public_key), notice: "Shoutout sent successfully!"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    @shoutout.destroy
    redirect_to my_shoutouts_path(tab: "given"), notice: "Shoutout deleted successfully."
  end

  private

  def set_shoutee
    shoutee_type = params[:shoutee_type]
    shoutee_id = params[:shoutee_id]

    if shoutee_type.blank? || shoutee_id.blank?
      redirect_to my_shoutouts_path, alert: "Please select a person or group to give a shoutout to."
      return
    end

    @shoutee = case shoutee_type
    when "Person"
      Person.find_by(id: shoutee_id)
    when "Group"
      Group.find_by(id: shoutee_id)
    end

    if @shoutee.nil?
      redirect_to my_shoutouts_path, alert: "Could not find the specified person or group."
    elsif @shoutee == Current.user.person
      redirect_to my_shoutouts_path, alert: "You cannot give a shoutout to yourself."
    end
  end

  def set_shoutout
    @shoutout = Current.user.person.given_shoutouts.find_by(id: params[:id])
    unless @shoutout
      redirect_to my_shoutouts_path, alert: "Shoutout not found."
    end
  end

  def shoutout_params
    params.require(:shoutout).permit(:content)
  end
end
