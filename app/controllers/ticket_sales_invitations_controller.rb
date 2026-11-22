# frozen_string_literal: true

# Accepting a share of a show's ticket sales (the show page → Who can see
# sales → invite by email). Someone with a CocoScout account signs in with
# its password or a code; someone new makes one right here. Then the waiting share is
# theirs and they land on their Ticket Sales. Mirrors DoorInvitationsController.
class TicketSalesInvitationsController < ApplicationController
  layout "door"

  include InvitationSignIn

  allow_unauthenticated_access
  before_action :set_viewer

  def show
    @existing_user = User.find_by(email_address: @viewer.invited_email)
  end

  def accept
    user = User.find_by(email_address: @viewer.invited_email)
    new_account = user.nil?
    if user
      # The right password, or already signed in to this account (for
      # example after signing in with a code and coming back).
      unless proved_invited_account?(user)
        @existing_user = user
        @error = "That password isn't right."
        render :show, status: :unprocessable_content and return
      end
    else
      # The invitation link came to this address, so opening it proves it.
      user = User.new(email_address: @viewer.invited_email, password: params[:password].to_s, email_verified_at: Time.current)
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
    start_invited_session(user, new_account: new_account)
    redirect_to shared_sales_path(user), notice: "You can now see the ticket sales for #{@viewer.scope_label}.", status: :see_other
  end

  private

  def set_viewer
    @viewer = TicketSalesViewer.active.find_by(invitation_token: params[:token].to_s)
    return if @viewer && @viewer.user_id.nil?

    redirect_to(Current.user ? my_shows_path : signin_path, alert: "That invitation has already been used or was withdrawn.")
  end

  # Where a share lands: its date's Tickets page under the show, or for a
  # whole production the next date on sale (there is no list of them).
  def shared_sales_path(user)
    listings = TicketSalesAccess.listings_for(user)
    listings = @viewer.scope_type == "TicketListing" ? listings.where(id: @viewer.scope_id) : listings.where(production_id: @viewer.scope_id)
    listing = listings.where("shows.date_and_time >= ?", Time.current).order("shows.date_and_time").first || listings.order("shows.date_and_time DESC").first
    listing ? my_show_tickets_path(listing.show_id) : my_shows_path
  end
end
