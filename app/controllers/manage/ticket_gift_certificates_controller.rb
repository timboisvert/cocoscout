# frozen_string_literal: true

module Manage
  # Gift certificates (TicketGiftCertificate): the organization's list, and
  # issuing one — a value, who it's for, what it's good for — whose code the
  # manager hands over or we email. Each has its own page: print it, or send
  # it to someone later (their name and email, the email seen before it
  # goes; Tim, 2026-10-30). Void stops a code that got out. Buyers spend them
  # on the checkout page (TicketGiftCertificates).
  class TicketGiftCertificatesController < Manage::TicketingBaseController
    before_action :set_certificate, only: %i[show print send_preview send_to void]

    def index
      @certificates = Current.organization.ticket_gift_certificates.includes(:issued_by, :voided_by, scopes: :production)
                             .order(created_at: :desc).to_a
      @issued = Current.organization.ticket_gift_certificates.find_by(id: params[:issued]) if params[:issued].present?
      @spent_orders = spent_orders(@certificates)
      # What "Only these" can pick from: productions with dates still to come.
      @scope_productions = upcoming_listings.select(&:production).group_by(&:production).sort_by { |production, _| production.name.downcase }
    end

    def create
      certificate = Current.organization.ticket_gift_certificates.new(certificate_params.merge(issued_by: Current.user))
      scopes = scope_rows
      if params[:good_for] == "some" && scopes.empty?
        return redirect_to manage_ticket_gift_certificates_path, alert: "Pick at least one production or date it's good for, or make it good for any show."
      end

      certificate.scope = scopes.any? ? "some" : "any"

      TicketGiftCertificate.transaction do
        certificate.save!
        scopes.each { |row| certificate.scopes.create!(row) }
      end
      emailed = params[:email_it] == "1" && certificate.recipient_email.present?
      TicketGiftCertificateEmailJob.perform_later(certificate.id) if emailed
      redirect_to manage_ticket_gift_certificates_path(issued: certificate.id, emailed: (1 if emailed))
    rescue ActiveRecord::RecordInvalid => e
      redirect_to manage_ticket_gift_certificates_path, alert: e.record.errors.full_messages.to_sentence
    end

    def show
      @orders = TicketGiftCertificateRedemption.where(ticket_gift_certificate: @certificate, status: "redeemed")
                                               .includes(:ticket_order).filter_map(&:ticket_order).uniq
    end

    # The certificate on paper, to hand over or mail.
    def print
      @profile = TicketingProfile.for(Current.organization)
      render layout: "print"
    end

    # Send it to someone: the email as it will arrive, to that name and
    # address, before anything is sent. A GET, so the preview renders
    # (Turbo drops a 200 answer to a POST).
    def send_preview
      @recipient_name = params[:recipient_name].to_s.strip
      @recipient_email = params[:recipient_email].to_s.strip.downcase
      error = send_error(@recipient_name, @recipient_email)
      return redirect_to(manage_ticket_gift_certificate_path(@certificate), alert: error) if error

      # Who it's for, in memory only, so the greeting reads right; nothing
      # changes until Send.
      @certificate.recipient_name = @recipient_name
      @email = TicketGiftCertificateMailer.rendered(@certificate)
    end

    # The certificate is now this person's: their name and email on it, and
    # the email on its way.
    def send_to
      name = params[:recipient_name].to_s.strip
      email = params[:recipient_email].to_s.strip.downcase
      error = send_error(name, email)
      return redirect_to(manage_ticket_gift_certificate_path(@certificate), alert: error) if error

      @certificate.update!(recipient_name: name, recipient_email: email)
      TicketGiftCertificateEmailJob.perform_later(@certificate.id)
      redirect_to manage_ticket_gift_certificate_path(@certificate), notice: "Sending #{@certificate.code} to #{name} at #{email}."
    end

    # A voided code stops working at checkout. Money already held by a
    # checkout in progress still settles; what's left is gone.
    def void
      @certificate.update!(voided_at: Time.current, voided_by: Current.user) unless @certificate.voided?
      redirect_to manage_ticket_gift_certificates_path, notice: "#{@certificate.code} is voided. It no longer works at checkout."
    end

    private

    def send_error(name, email)
      return "#{@certificate.code} is voided, so there's nothing to send." if @certificate.voided?
      return "#{@certificate.code} is used up, so there's nothing left to send." if @certificate.spent?
      return "Add the name of the person it's for." if name.blank?
      return "Add an email address to send it to." if email.blank?
      return "#{email} doesn't look like an email address." unless email.match?(URI::MailTo::EMAIL_REGEXP)

      nil
    end

    def set_certificate
      @certificate = Current.organization.ticket_gift_certificates.find(params[:id])
    end

    # The value is typed as dollars.
    def certificate_params
      permitted = params.require(:ticket_gift_certificate).permit(:amount, :recipient_name, :recipient_email, :note)
      amount = permitted.delete(:amount).to_s.delete("$,").strip
      permitted[:amount_cents] = amount.empty? ? 0 : (BigDecimal(amount) * 100).round.to_i
      permitted
    rescue ArgumentError
      { amount_cents: 0 }
    end

    # "Only these": productions[<id>][all]=1 means every date of it;
    # productions[<id>][listing_ids][] names some dates. Only this
    # organization's productions and dates count.
    def scope_rows
      return [] unless params[:good_for] == "some"

      raw = params[:productions]
      return [] unless raw.respond_to?(:each_pair)

      production_ids = Current.organization.productions.where(id: raw.keys.map(&:to_i)).pluck(:id)
      raw.each_pair.flat_map do |production_id, choice|
        next [] unless production_ids.include?(production_id.to_i) && choice.respond_to?(:[])

        listing_ids = Current.organization.ticket_listings.where(production_id: production_id.to_i, id: Array(choice[:listing_ids]).map(&:to_i)).pluck(:id)
        if listing_ids.any?
          listing_ids.map { |listing_id| { production_id: production_id.to_i, ticket_listing_id: listing_id } }
        elsif choice[:all] == "1"
          [ { production_id: production_id.to_i } ]
        else
          []
        end
      end
    end

    # The orders each spent certificate paid for, for the list.
    def spent_orders(certificates)
      TicketGiftCertificateRedemption.where(ticket_gift_certificate_id: certificates.map(&:id), status: "redeemed")
                                     .includes(:ticket_order).group_by(&:ticket_gift_certificate_id)
                                     .transform_values { |rows| rows.filter_map(&:ticket_order) }
    end
  end
end
