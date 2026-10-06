# frozen_string_literal: true

# Accepting a share of a show's ticket sales (the show page → Who can see
# sales → invite by email). Someone with a CocoScout account signs in with
# its password; someone new makes one right here. Then the waiting share is
# theirs and they land on their Ticket Sales. Mirrors DoorInvitationsController.
class TicketSalesInvitationsController < ApplicationController
  layout "door"

  allow_unauthenticated_access
  before_action :set_viewer

  def show
    @existing_user = User.find_by(email_address: @viewer.invited_email)
  end

  def accept
    user = User.find_by(email_address: @viewer.invited_email)
    if user
      unless user.authenticate(params[:password].to_s)
        @existing_user = user
        @error = "That password isn't right."
        render :show, status: :unprocessable_content and return
      end
    else
      user = User.new(email_address: @viewer.invited_email, password: params[:password].to_s)
      unless user.save
        @error = user.errors.full_messages.to_sentence
        render :show, status: :unprocessable_content and return
      end
      person = Person.where(email: @viewer.invited_email, user_id: nil).first ||
               Person.new(email: @viewer.invited_email, name: @viewer.invited_name.presence || @viewer.invited_email.split("@").first)
      person.update!(user: user)
      user.update!(default_person: person)
    end

    @viewer.accept!(user)
    start_new_session_for(user)
    redirect_to my_ticket_sales_path, notice: "You can now see the ticket sales for #{@viewer.scope_label}.", status: :see_other
  end

  private

  def set_viewer
    @viewer = TicketSalesViewer.active.find_by(invitation_token: params[:token].to_s)
    return if @viewer && @viewer.user_id.nil?

    redirect_to(Current.user ? my_ticket_sales_path : signin_path, alert: "That invitation has already been used or was withdrawn.")
  end
end
