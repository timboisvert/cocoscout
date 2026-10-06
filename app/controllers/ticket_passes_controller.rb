# frozen_string_literal: true

# A pass's public page (/tickets/<org>/passes/<slug>): the shows in it, its
# all-in price against buying them separately, and a stepper. Continuing
# holds a seat at every show (TicketCheckout.start_pass!) and opens the usual
# checkout. Box office rules apply: the theater's ticketing must be on, or
# the viewer a superadmin previewing.
class TicketPassesController < TicketsController
  # Like the show pages' checkout: the embed can't carry our session.
  skip_forgery_protection only: :checkout

  def show
    @pass = find_pass
    @rows = @pass.rows
    @selling = @pass.selling?(Time.current, @rows)
    @remaining = @pass.remaining(@rows)
  end

  def checkout
    if params[:website].present?
      Rails.logger.warn("[TicketPasses] honeypot tripped on start ip=#{request.remote_ip}")
      return redirect_to(tickets_pass_path(org: params[:org], pass: params[:pass], **embed_params))
    end

    order = TicketCheckout.start_pass!(pass: find_pass, quantity: params[:quantity], client_ip: request.remote_ip,
                                       referrer: request.referer, via: cookies[ShortLinksController::COOKIE])
    redirect_to tickets_checkout_path(token: order.token, **embed_params)
  rescue TicketCheckout::Error => e
    redirect_to tickets_pass_path(org: params[:org], pass: params[:pass], **embed_params), alert: e.message
  end

  private

  # A draft is only for a superadmin checking it.
  def find_pass
    pass = @organization.ticket_passes.find_by!(slug: params[:pass].to_s)
    raise ActiveRecord::RecordNotFound if pass.status == "draft" && !superadmin_viewer?

    pass
  end
end
