# frozen_string_literal: true

# Accepting an invitation to work a theater's door (Ticketing settings →
# Door access → invite by email). Someone with a CocoScout account signs in
# with its password; someone new makes one right here. Either way the
# waiting grant becomes theirs and they land on /door. Mirrors
# Manage::TeamInvitationsController#accept / #do_accept.
class DoorInvitationsController < ApplicationController
  layout "door"

  allow_unauthenticated_access
  before_action :set_grant

  def show
    @existing_user = User.find_by(email_address: @grant.invited_email)
  end

  def accept
    user = User.find_by(email_address: @grant.invited_email)
    if user
      unless user.authenticate(params[:password].to_s)
        @existing_user = user
        @error = "That password isn't right."
        render :show, status: :unprocessable_content and return
      end
    else
      user = User.new(email_address: @grant.invited_email, password: params[:password].to_s)
      unless user.save
        @error = user.errors.full_messages.to_sentence
        render :show, status: :unprocessable_content and return
      end
      person = Person.where(email: @grant.invited_email, user_id: nil).first ||
               Person.new(email: @grant.invited_email, name: @grant.invited_name.presence || @grant.invited_email.split("@").first)
      person.update!(user: user)
      user.update!(default_person: person)
    end

    @grant.accept!(user)
    start_new_session_for(user)
    redirect_to door_index_path, notice: "You can now work the door at #{@grant.organization.name}.", status: :see_other
  end

  private

  def set_grant
    @grant = TicketingAccessGrant.active.find_by(invitation_token: params[:token].to_s)
    return if @grant && @grant.user_id.nil?

    redirect_to(Current.user ? door_index_path : signin_path, alert: "That invitation has already been used or was withdrawn.")
  end
end
