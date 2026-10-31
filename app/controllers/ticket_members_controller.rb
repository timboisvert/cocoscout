# frozen_string_literal: true

# The members page (/tickets/<org>/members, advanced ticketing §2b): the
# levels on sale with their perks and a Join button; "Already a member?"
# sign-in by emailed code (Ticketing::BuyerVerification), which sets the
# thirty-day cookie; a signed-in member sees their card. Box office rules
# apply: the organization's ticketing must be on.
class TicketMembersController < TicketsController
  skip_forgery_protection only: %i[join code verify signout]

  def show
    @levels = @organization.ticket_membership_levels.on_sale.in_order.to_a
    @email = verified_buyer_email(@organization)
    @membership = current_membership(@organization)
    @past = @email ? @organization.ticket_memberships.where(holder_email: @email).where.not(status: %w[pending active]).includes(:level).order(ends_on: :desc).first : nil
    @asking = params[:email].present?
  end

  def join
    return redirect_to(members_path) if params[:website].present?

    level = @organization.ticket_membership_levels.on_sale.find(params[:level_id])
    purchase = Ticketing::Memberships.start!(level: level, email: verified_buyer_email(@organization))
    redirect_to tickets_membership_purchase_path(token: purchase.token, **embed_params)
  rescue Ticketing::Memberships::Error => e
    redirect_to members_path, alert: e.message
  end

  def code
    return redirect_to(members_path) if params[:website].present?

    email = Ticketing::BuyerVerification.send_code!(@organization, params[:email])
    redirect_to members_path(email: email), notice: "We emailed a code to #{email}. Type it here."
  rescue Ticketing::BuyerVerification::Error => e
    redirect_to members_path, alert: e.message
  end

  def verify
    email = params[:email].to_s.strip.downcase
    Ticketing::BuyerVerification.check!(@organization, email, params[:code])
    verify_buyer!(@organization, email)
    redirect_to members_path, notice: "You're signed in."
  rescue Ticketing::BuyerVerification::Error => e
    redirect_to members_path(email: email), alert: e.message
  end

  def signout
    forget_buyer!(@organization)
    redirect_to members_path, notice: "Signed out."
  end

  private

  def members_path(**extra)
    tickets_members_path(org: @ticketing_profile.slug, **embed_params, **extra)
  end
end
