# frozen_string_literal: true

class Contract < ApplicationRecord
  belongs_to :organization
  belongs_to :contractor, optional: true

  has_many :contract_documents, dependent: :destroy
  has_many :contract_payments, dependent: :destroy
  has_many :space_rentals, dependent: :destroy
  # A contract is FOR one production (the real-world show). A production can be the
  # subject of many contracts over time — see Production#contracts.
  belongs_to :production, optional: true
  # The template whose wording rendered this contract's signable document (only
  # set for e-sign contracts; offline contracts never pick one).
  belongs_to :contract_template, optional: true
  has_many :course_offerings, dependent: :nullify
  has_many :contract_signatures, dependent: :destroy

  # Status enum
  enum :status, {
    draft: "draft",
    active: "active",
    completed: "completed",
    cancelled: "cancelled"
  }, default: :draft, prefix: :status

  # How this contract's signature is handled. :offline is the classic behavior
  # (signed elsewhere, PDF optionally uploaded) and the default for every existing
  # contract. :esign engages CocoScout's native create → send → sign → PDF flow.
  enum :signing_mode, {
    offline: "offline",
    esign: "esign"
  }, default: :offline, prefix: :signing_mode

  # Native-signing lifecycle (esign contracts only):
  #   unsent → awaiting_send → out_for_signature → executed
  # unsent: still being prepared/signed by the org side (wizard Prepare/Sign steps).
  # awaiting_send: the org has signed; the document is locked and ready to send.
  # out_for_signature: sent to the counterparty. executed: they signed.
  # Independent of :status (draft/active/…) — execution auto-activates the contract.
  enum :signing_state, {
    unsent: "unsent",
    awaiting_send: "awaiting_send",
    out_for_signature: "out_for_signature",
    executed: "executed"
  }, default: :unsent, prefix: :signing

  validates :contractor_name, presence: true

  # Merge tokens a template can drop inside its own wording to place deal content
  # inline, instead of relying on the Deal Terms schedule appended at the end.
  # {{license_schedule}} → the dates/stage/rent grid; {{services}} → the service
  # line items. When a template uses either, the appended block is suppressed so
  # nothing is duplicated — see #render_document_for.
  LICENSE_SCHEDULE_TOKEN = "{{license_schedule}}"
  SERVICES_TOKEN = "{{services}}"

  # Ways money can reach us that aren't the online pay link. Each must be
  # allowed on the contract before a manager may record one.
  OFFLINE_PAYMENT_METHODS = %w[check bank_transfer cash].freeze

  # Labels for the offline methods, in the order they're offered.
  OFFLINE_PAYMENT_METHOD_LABELS = {
    "check" => "Check",
    "bank_transfer" => "Bank transfer",
    "cash" => "Cash"
  }.freeze

  # Callbacks to sync contractor data
  before_save :sync_contractor_info

  # Scopes
  scope :recent, -> { order(created_at: :desc) }
  scope :upcoming, -> { status_active.where("contract_end_date >= ?", Date.current).order(:contract_start_date) }
  scope :past, -> { where("contract_end_date < ?", Date.current).order(contract_end_date: :desc) }

  # Allow overlap flag - when true, skip overlap validation on space rentals
  attr_accessor :allow_overlap

  # Lifecycle methods
  def activate!
    activated = false

    # Lock the row for the whole activation so two concurrent activate requests
    # (double-click, or the wizard + money endpoints firing together) can't both
    # pass the draft check and each create a duplicate production/shows/payments.
    # The second caller blocks here, then sees status == active and no-ops.
    with_lock do
      next unless status_draft?
      next unless valid_for_activation?

      create_records_from_draft!

      update!(
        status: :active,
        activated_at: Time.current,
        skip_event_creation: false
        # Keep draft_data - it contains the full contract config (services, payment_config, etc.)
      )
      activated = true
    end

    activated
  rescue ActiveRecord::RecordInvalid => e
    errors.add(:base, e.message)
    false
  end

  def complete!
    return false unless status_active?

    transaction do
      update!(
        status: :completed,
        completed_at: Time.current
      )

      # Archive the production only if no OTHER active contract still uses it
      # (a production can be shared by several contracts over time).
      if production && production.contracts.status_active.where.not(id: id).none? && !production.archived?
        production.update!(archived_at: Time.current)
      end
    end

    true
  end

  # Reverse a completion so the contract can be extended again — e.g. a teacher
  # ran a course in June and you now want to add August dates and reuse the
  # contract. Flips completed → active and un-archives the production that was
  # archived on completion, so amending (and selecting it for a new course) works.
  def reopen!
    return false unless status_completed?

    transaction do
      update!(status: :active, completed_at: nil)
      production.update!(archived_at: nil) if production&.archived?
    end

    true
  end

  def cancel!(delete_events: false)
    return false if status_cancelled?

    transaction do
      if delete_events
        # Remove only THIS contract's shows (the production may be shared with
        # other contracts, so we never destroy the whole production here).
        # Unlink referencing payments first — contract_payments.show_id has a FK
        # that blocks deleting a referenced show (and those payments may belong
        # to other contracts, so we drop the link, not the payment).
        show_ids = contract_shows.pluck(:id)
        ContractPayment.where(show_id: show_ids).update_all(show_id: nil) if show_ids.any?
        contract_shows.destroy_all
      else
        contract_shows.update_all(canceled: true)
      end

      update!(
        status: :cancelled,
        cancelled_at: Time.current
      )
    end

    true
  end

  # ─── Native e-signature ─────────────────────────────────────────────────────

  # The counterparty's CocoScout member Person, if they already have a login — so
  # we can tell them the contract will also appear in their My Contracts. Resolves
  # the linked contractor Person, else matches an org Person by email; returns it
  # only when it's a real member (has a user account). Never creates anything.
  def signer_member_person
    person = contractor&.person
    person ||= organization.people.where("LOWER(email) = ?", contractor_email.to_s.downcase).first if contractor_email.present?
    person if person&.user_id.present?
  end

  def signer_is_member?
    signer_member_person.present?
  end

  def organization_signature
    contract_signatures.detect(&:role_organization?) ||
      contract_signatures.role_organization.first
  end

  def contractor_signature
    contract_signatures.detect(&:role_contractor?) ||
      contract_signatures.role_contractor.first
  end

  # The generated (or uploaded) signed-contract PDF, if one is attached. Uses the
  # loaded association (so a preloaded index doesn't re-query per card).
  def signed_pdf_document
    contract_documents.to_a.select { |d| d.document_type == "signed_contract" }.detect { |d| d.file.attached? }
  end

  # Kick off signed-PDF generation if this is executed but has none yet. Safe to
  # call from a view/GET — the job is idempotent and no-ops when a PDF exists.
  def ensure_signed_pdf!
    GenerateContractPdfJob.perform_later(id) if signing_executed? && signed_pdf_document.nil?
  end

  # Mint a fresh public signing token (rotates any prior one — an old link dies).
  def regenerate_signing_token!
    update!(signing_token: SecureRandom.urlsafe_base64(24))
  rescue ActiveRecord::RecordNotUnique
    retry
  end

  # Prepare (wizard "Prepare" step): lock in the template whose wording will render
  # the document. The producer previews the rendered contract before this. Idempotent
  # — they can re-pick and re-preview until they sign.
  def prepare_for_signature!(template:)
    raise ArgumentError, "not an e-sign contract" unless signing_mode_esign?
    raise ArgumentError, "template required" if template.nil?
    return false if signing_executed? || signing_out_for_signature?

    update!(contract_template: template)
    true
  end

  # Org signs (wizard "Sign" step): the org's own deliberate signature, stamped with
  # the producer + timestamp + IP, over the locked document snapshot. Moves the
  # contract to awaiting_send — nothing has gone to the counterparty yet.
  def sign_by_org!(signer_name:, signed_by:, request:)
    raise ArgumentError, "choose a template first" if contract_template.nil?
    return false if signing_executed? || signing_out_for_signature?

    transaction do
      snapshot = render_signable_document
      contract_signatures.role_organization.destroy_all
      contract_signatures.create!(
        signer_role: "organization",
        signer_name: signer_name.presence || signed_by&.person&.name.presence || organization.name,
        signer_email: signed_by&.person&.email.presence || signed_by&.email_address,
        signed_by_user: signed_by,
        person: signed_by&.person,
        signed_at: Time.current,
        ip_address: request&.remote_ip,
        user_agent: request&.user_agent&.truncate(500),
        content_snapshot: snapshot,
        contract_template: contract_template,
        template_version: contract_template.version
      )
      update!(signing_state: :awaiting_send)
    end
    true
  end

  # Send (wizard "Send" step): the org has signed; now mint a fresh link and put it
  # out for the counterparty to sign. (Templated email + in-app message are enqueued
  # by the caller.)
  def send_for_signature!
    return false unless signing_awaiting_send?

    regenerate_signing_token!
    update!(signing_state: :out_for_signature, sent_for_signature_at: Time.current)
    true
  end

  # Pull back a sent-but-unsigned request: the link dies. The org's signature and
  # locked document are kept, so it drops back to awaiting_send — re-send in one
  # click, or step back to change the data / template and re-sign first.
  def revoke_signing!
    return false unless signing_out_for_signature?

    update!(signing_state: :awaiting_send, signing_token: nil, sent_for_signature_at: nil)
    true
  end

  # Counterparty agrees on the public sign page → contract is executed. Both
  # parties' snapshots are the identical document the org sent. Executing an
  # esign contract also activates it (creates its operational records).
  def execute_by_signature!(signer_name:, signer_email:, request:, person: nil)
    return false unless signing_out_for_signature?

    transaction do
      snapshot = organization_signature&.content_snapshot.presence || render_signable_document
      contract_signatures.role_contractor.destroy_all
      contract_signatures.create!(
        signer_role: "contractor",
        signer_name: signer_name,
        signer_email: signer_email,
        person: person,
        signed_at: Time.current,
        ip_address: request.remote_ip,
        user_agent: request.user_agent&.truncate(500),
        content_snapshot: snapshot,
        contract_template: contract_template,
        template_version: contract_template&.version
      )
      # Keep the token alive after execution so the signer can return to their
      # link for the signed PDF; only revoke nulls it.
      update!(signing_state: :executed, executed_at: Time.current)
    end

    # Best-effort: a fully-signed contract becomes operational. If activation
    # can't complete (e.g. a booking conflict), it stays executed-but-draft for
    # the producer to resolve — the signature record is already safe.
    activate! if status_draft?
    # Generate the signed PDF off the request thread.
    GenerateContractPdfJob.perform_later(id)
    # Tell the org's chosen managers it was signed (in-app message only).
    ContractSignedNotificationJob.perform_later(id)
    true
  end

  # The merge values a contract template renders against.
  def signing_variables
    {
      contractor_name: contractor_name,
      organization_name: organization.name,
      production_name: production_name.presence || production&.name,
      contract_start_date: contract_start_date&.strftime("%B %-d, %Y"),
      contract_end_date: contract_end_date&.strftime("%B %-d, %Y"),
      current_date: Date.current.strftime("%B %-d, %Y")
    }
  end

  # The full signable document for the locked template: the wording (merge-filled)
  # followed by a system-generated "Deal Terms" schedule so the concrete
  # dates/money/services are always accurate regardless of what the author wrote.
  def render_signable_document
    render_document_for(contract_template)
  end

  # Same, for an arbitrary template — used to preview before locking one in.
  # Interpolate (don't use +) so the safe template HTML and the Deal Terms HTML are
  # joined as plain strings and neither half gets auto-escaped; mark the whole safe.
  #
  # If the template drops an inline token ({{license_schedule}} and/or {{services}})
  # in its wording, it's placing that deal content itself, so we fill the tokens
  # inline (raw HTML, not escaped) and skip the appended Deal Terms block — the
  # template's prose already carries the money terms. Templates without any inline
  # token keep the classic append. gsub is a no-op when a token is absent, so both
  # substitutions run unconditionally.
  def render_document_for(template)
    body = template ? template.render_content(signing_variables).to_s : ""
    uses_inline = body.include?(LICENSE_SCHEDULE_TOKEN) || body.include?(SERVICES_TOKEN)
    body = body.gsub(LICENSE_SCHEDULE_TOKEN, license_schedule_html)
    body = body.gsub(SERVICES_TOKEN, license_services_html)
    uses_inline ? body.html_safe : "#{body}#{deal_terms_html}".html_safe
  end

  # Draft data helpers
  def draft_bookings
    draft_data["bookings"] || []
  end

  def draft_booking_rules
    draft_data["booking_rules"] || {}
  end

  def draft_payments
    draft_data["payments"] || []
  end

  def draft_payment_structure
    draft_data["payment_structure"] || "flat_fee"
  end

  def draft_payment_config
    draft_data["payment_config"] || {}
  end

  def draft_ticketing
    draft_data["ticketing"] || {}
  end

  # Discount codes on a ticketing hash, as an array. Ticketing used to hold one
  # `discount`; it now holds a `discounts` list. Normalizes either shape so
  # readers don't have to care which a given contract was saved with.
  def self.ticketing_discounts(ticketing)
    ticketing ||= {}
    list = ticketing["discounts"]
    return list if list.is_a?(Array) && list.any?

    single = ticketing["discount"]
    single.is_a?(Hash) && single["code"].present? ? [ single ] : []
  end

  def draft_tech
    draft_data["tech"] || {}
  end

  # Per-contract service line items: [{ "name", "quantity", "unit_price", "direction" }].
  def draft_services
    draft_data["services"] || []
  end

  # Turn a set of service line items into billable ContractPayments (one per line
  # with a positive amount). Used at activation.
  def bill_services!(services)
    Array(services).each do |service|
      amount = (service["quantity"].to_f * service["unit_price"].to_f).round(2)
      next unless amount.positive?

      contract_payments.create!(
        description: service["name"],
        amount: amount,
        direction: service["direction"].presence || "incoming",
        due_date: contract_end_date || Date.current
      )
    end
  end

  # Re-bill services when a contract is amended: drop the still-pending payments
  # for the current set, record the new set, and bill it. Paid service payments
  # are never touched, so nothing that's already been settled is disturbed.
  def reconcile_service_payments!(new_services)
    old_names = draft_services.map { |s| s["name"] }.compact
    contract_payments.status_pending.where(description: old_names).destroy_all if old_names.any?
    update_draft_step(:services, Array(new_services))
    bill_services!(draft_services)
  end

  # Amend: apply a freshly-edited payment list (the deal-derived payments plus any
  # by-hand extras, produced by the same Financials editor as create) to an active
  # contract. Paid payments are history and stay put; every pending payment is
  # replaced by the staged list, and per-event payments are re-linked to shows.
  def reconcile_amended_payments!(staged_payments)
    contract_payments.status_pending.destroy_all

    created = Array(staged_payments).filter_map do |payment|
      tbd = payment["amount_tbd"] == true || payment["amount_tbd"] == "true"
      next if payment["amount"].to_f <= 0 && !tbd

      contract_payments.create!(
        description: payment["description"],
        amount: payment["amount"].to_f,
        amount_tbd: tbd,
        direction: payment["direction"].presence || settlement_direction,
        due_date: payment["due_date"].present? ? Date.parse(payment["due_date"].to_s) : (contract_end_date || Date.current),
        notes: payment["notes"]
      )
    end

    link_payments_to_shows(created, contract_shows.order(:date_and_time).to_a)
  end

  def update_draft_step(step_name, data)
    self.draft_data = draft_data.merge(step_name.to_s => data)
    save!
  end

  # Amend data helpers (for amending existing active contracts)
  def amend_data
    draft_data["amend"] || {}
  end

  def update_amend_data(data)
    self.draft_data = draft_data.merge("amend" => data)
    save!
  end

  def clear_amend_data
    new_data = draft_data.except("amend")
    self.draft_data = new_data
    save!
  end

  # Validation for activation
  def valid_for_activation?
    errors.clear

    errors.add(:base, "Must have at least one booking") if draft_bookings.empty? && space_rentals.empty?
    errors.add(:base, "Contract start date is required") if contract_start_date.blank?
    errors.add(:base, "Contract end date is required") if contract_end_date.blank?

    errors.empty?
  end

  # How this contract's money maps into the org's Money totals, so contract money
  # isn't siloed — it flows into revenue and payout totals like everything else.
  #
  # Gross model: when WE sell the tickets, the full ticket revenue is money coming
  # in and the contractor's share is a payout going out (profit = our cut). When
  # THEY sell, we only ever see our cut (money in, nothing out). Flat deals fall
  # back to the contract's own payments by direction.
  #
  # Returns { money_in:, money_out: } in dollars.
  def money_summary
    if revenue_share?
      summary = revenue_share_summary
      return { money_in: 0.0, money_out: 0.0 } unless summary

      if who_sells_tickets == "org"
        { money_in: summary[:confirmed_revenue], money_out: summary[:contractor_share] }
      else
        { money_in: summary[:our_share], money_out: 0.0 }
      end
    elsif ticket_revenue_minus_fee?
      summary = flat_fee_revenue_summary
      return { money_in: 0.0, money_out: 0.0 } unless summary

      # We sell, keep a fee, hand back the rest: full revenue in, their remainder out.
      { money_in: summary[:confirmed_revenue], money_out: summary[:contractor_share] }
    else
      # Flat deals: the contract's own payments are the money, by direction.
      {
        money_in: contract_payments.where(direction: "incoming").sum(:amount).to_f,
        money_out: contract_payments.where(direction: "outgoing").sum(:amount).to_f
      }
    end
  end

  # Financial summary
  def total_incoming
    contract_payments.where(direction: "incoming", status: "paid").sum(:amount)
  end

  def total_outgoing
    contract_payments.where(direction: "outgoing").sum(:amount)
  end

  def net_amount
    total_incoming - total_outgoing
  end

  def pending_payments
    contract_payments.where(status: "pending")
  end

  def overdue_payments
    contract_payments.where(status: "pending").where("due_date < ?", Date.current)
  end

  # Shows covered by THIS contract. When the production is shared by several
  # contracts, each contract only "owns" the shows booked through its own space
  # rentals. When the production belongs to only this contract, all of its shows
  # are this contract's (covers any show created without an explicit rental).
  def contract_shows
    rental_show_ids = Show.where(space_rental_id: space_rentals.select(:id)).select(:id)

    if production_id.present? && production && production.contracts.count <= 1
      Show.where(production_id: production_id).or(Show.where(id: rental_show_ids))
    else
      Show.where(id: rental_show_ids)
    end
  end

  # Revenue share financial helpers — calculates from show-level financials
  def contractor_share_percentage
    return nil unless revenue_share?
    100.0 - revenue_share_percentage
  end

  # Returns { confirmed_revenue: X, tbd_count: N, contractor_share: Y }
  def revenue_share_summary
    return nil unless revenue_share?

    all_shows = contract_shows.includes(:show_financials).to_a
    confirmed_shows = all_shows.select { |s| s.show_financials&.has_data? }
    pending_shows = all_shows - confirmed_shows

    confirmed_revenue = confirmed_shows.sum { |s| s.show_financials.total_revenue }
    our_share_amount = (confirmed_revenue * revenue_share_percentage / 100.0).round(2)
    contractor_share_amount = (confirmed_revenue * contractor_share_percentage / 100.0).round(2)

    {
      confirmed_revenue: confirmed_revenue,
      confirmed_count: confirmed_shows.count,
      pending_count: pending_shows.count,
      our_share: our_share_amount,
      contractor_share: contractor_share_amount,
      total_shows: all_shows.count
    }
  end

  # Returns financial summary for ticket_revenue_minus_fee contracts
  def flat_fee_revenue_summary
    return nil unless ticket_revenue_minus_fee?

    all_shows = contract_shows.includes(:show_financials).to_a
    confirmed_shows = all_shows.select { |s| s.show_financials&.has_data? }
    pending_shows = all_shows - confirmed_shows

    confirmed_revenue = confirmed_shows.sum { |s| s.show_financials.total_revenue }
    fee = flat_fee_amount
    contractor_amount = [ confirmed_revenue - fee, 0 ].max

    {
      confirmed_revenue: confirmed_revenue,
      confirmed_count: confirmed_shows.count,
      pending_count: pending_shows.count,
      our_share: fee,
      contractor_share: contractor_amount,
      total_shows: all_shows.count
    }
  end

  # Find the matching ContractPayment for a given show based on settlement frequency
  def find_payment_for_show(show)
    return nil unless revenue_share?

    # First, try direct show_id link
    direct = contract_payments.find_by(show_id: show.id)
    return direct if direct

    settlement = draft_payment_config["revenue_settlement"] || "monthly"
    # Direction-agnostic: contracts can be incoming (contractor pays us) or outgoing (we pay contractor)
    revenue_payments = contract_payments.where(amount_tbd: true)
                                        .or(contract_payments.where("description LIKE ?", "%Revenue Share%"))
                                        .order(:due_date)

    payment = case settlement
    when "per_event", "next_day", "same_day"
      # Match by positional order: sort shows and payments by date, pair 1:1
      all_shows = contract_shows.order(:date_and_time).to_a
      show_index = all_shows.index { |s| s.id == show.id }
      show_index ? revenue_payments.to_a[show_index] : nil
    when "weekly"
      show_week_start = show.date_and_time.to_date.beginning_of_week
      revenue_payments.find { |p| p.due_date.beginning_of_week == show_week_start }
    else # monthly
      show_month = show.date_and_time.to_date.beginning_of_month
      revenue_payments.find { |p| p.due_date.beginning_of_month == show_month }
    end

    # Link the show_id for future lookups if we found a match
    if payment && payment.show_id.nil?
      payment.update_column(:show_id, show.id)
    end

    payment
  end

  # Get all shows that map to a given ContractPayment
  def shows_for_payment(payment)
    # If payment has a direct show link, use it
    if payment.show_id.present?
      show = Show.includes(:show_financials).find_by(id: payment.show_id)
      return show ? [ show ] : []
    end

    settlement = draft_payment_config["revenue_settlement"] || "monthly"
    all_shows = contract_shows.includes(:show_financials).order(:date_and_time).to_a

    case settlement
    when "per_event", "next_day", "same_day"
      # Match by positional order: sort payments by due_date, pair 1:1 with shows by date
      revenue_payments = contract_payments.where("amount_tbd = ? OR description LIKE ?", true, "%Revenue Share%")
                                          .order(:due_date).to_a
      payment_index = revenue_payments.index { |p| p.id == payment.id }
      show = payment_index ? all_shows[payment_index] : nil
      if show
        # Link for future lookups
        payment.update_column(:show_id, show.id) if payment.show_id.nil?
        [ show ]
      else
        []
      end
    when "weekly"
      week_start = payment.due_date.beginning_of_week
      all_shows.select { |s| s.date_and_time.to_date.beginning_of_week == week_start }
    else # monthly
      month_start = payment.due_date.beginning_of_month
      all_shows.select { |s| s.date_and_time.to_date.beginning_of_month == month_start }
    end
  end

  # Display helpers
  def display_name
    production_name.presence || contractor_name
  end

  def date_range
    return nil if contract_start_date.blank? || contract_end_date.blank?

    if contract_start_date == contract_end_date
      contract_start_date.strftime("%B %d, %Y")
    else
      "#{contract_start_date.strftime('%B %d')} - #{contract_end_date.strftime('%B %d, %Y')}"
    end
  end

  # Revenue projection helpers. These read the v2 settlement_basis, which falls
  # back to the legacy payment_structure — so old and migrated contracts both work.
  def revenue_share?
    settlement_basis == "revenue_share"
  end

  def ticket_revenue_minus_fee?
    settlement_basis == "revenue_minus_fee"
  end

  def flat_fee_amount
    draft_payment_config["flat_fee_amount"].to_f
  end

  def revenue_share_percentage
    return nil unless revenue_share?
    draft_payment_config["revenue_our_share"].to_f
  end

  # --- Payment model v2: who sells tickets + settlement basis ---
  # Every contract's money flow is two orthogonal choices. Stored in
  # draft_payment_config; these getters fall back to the legacy payment_structure
  # so existing contracts keep working until the backfill task migrates them.

  # Who sells the tickets: "org" (we do), "contractor" (they do), or nil (this
  # deal doesn't involve tickets at all).
  #
  # This is a separate question from how the deal settles. We might sell the
  # tickets and keep every penny while they simply pay us a flat rental — so
  # this says who holds the ticket money and whether we need ticket tiers, not
  # who owes whom.
  def who_sells_tickets
    draft_payment_config["who_sells_tickets"].presence || legacy_who_sells_tickets
  end

  # True when we're the ones selling, so this contract needs ticketing set up.
  def org_sells_tickets?
    who_sells_tickets == "org"
  end

  # Case 2: the contractor sells their own tickets on a revenue split, so they
  # self-report the sales and then owe us our cut. This is the only case where a
  # contractor enters ticket numbers themselves.
  def contractor_reports_sales?
    who_sells_tickets == "contractor" && revenue_share?
  end

  # "revenue_share" | "revenue_minus_fee" | "flat".
  def settlement_basis
    draft_payment_config["settlement_basis"].presence || legacy_settlement_basis
  end

  # Which way money flows for the core settlement.
  #
  # For a ticket split, it follows whoever holds the ticket money: we sell, so we
  # pay them their share (outgoing); they sell, so they pay us ours (incoming).
  # Ticket-revenue-minus-fee is always us selling and handing back the remainder.
  # A flat fee is independent of ticketing — a rental where we still sell the
  # tickets is money coming IN — so it uses its own stated direction.
  def settlement_direction
    case settlement_basis
    when "revenue_share"
      who_sells_tickets == "org" ? "outgoing" : "incoming"
    when "revenue_minus_fee"
      "outgoing"
    else
      dir = draft_payment_config["flat_fee_direction"]
      dir.in?(%w[incoming outgoing]) ? dir : "incoming"
    end
  end

  # --- How they're allowed to pay us -----------------------------------------
  # Online is always available (that's the Stripe pay link). The rest are ways
  # money can reach us outside CocoScout, and each has to be allowed explicitly
  # before we'll let anyone record one by hand.

  # Ways a contractor may pay us, defaulting to the org's policy.
  def accepted_payment_methods
    configured = draft_payment_config["accepted_payment_methods"]
    configured = organization&.default_contract_payment_methods if configured.blank?
    ([ "online" ] + (Array(configured) & OFFLINE_PAYMENT_METHODS)).uniq
  end

  # The allowed offline methods, in the order they're offered.
  def offline_payment_methods
    accepted_payment_methods - [ "online" ]
  end

  # True when this contract allows money to reach us outside Stripe, so a
  # manager may record a payment by hand.
  def offline_payments_allowed?
    offline_payment_methods.any?
  end

  # A plain-English summary of the deal for the review step — every term that
  # was set on Financials, so nobody has to click back to check. Returns an
  # array of { label:, value: } with money pre-formatted.
  def deal_summary
    cfg = draft_payment_config
    lines = []

    who_sells_label = case who_sells_tickets
    when "org" then "We do"
    when "contractor" then "They do — they report their sales"
    else "No tickets on this deal"
    end
    lines << { label: "Who sells the tickets", value: who_sells_label }

    case draft_payment_structure
    when "flat_fee"
      deal_summary_flat_fee(cfg, lines)
    when "per_event"
      deal_summary_per_event(cfg, lines)
    when "revenue_share"
      deal_summary_revenue_share(cfg, lines)
    end

    methods = accepted_payment_methods.map do |m|
      m == "online" ? "online" : OFFLINE_PAYMENT_METHOD_LABELS[m]&.downcase
    end.compact
    lines << { label: "They may pay us by", value: methods.to_sentence }

    lines
  end

  # Flat-fee entries — supports one whole-contract fee, a uniform per-event fee,
  # or a per-event fee with a different price per event. Returns an array of
  # { "amount", "due_date", "show_index" } (show_index nil = whole contract).
  def flat_fee_entries
    entries = draft_payment_config["flat_fee_entries"]
    return entries if entries.is_a?(Array) && entries.any?

    [ { "amount" => flat_fee_amount, "due_date" => nil, "show_index" => nil } ]
  end

  def legacy_settlement_basis
    case draft_payment_structure
    when "revenue_share" then "revenue_share"
    when "flat_fee"
      draft_payment_config["flat_fee_direction"] == "ticket_revenue_minus_fee" ? "revenue_minus_fee" : "flat"
    else "flat" # per_event / custom → a list of flat amounts
    end
  end

  def legacy_who_sells_tickets
    case legacy_settlement_basis
    when "revenue_minus_fee" then "org"     # we sell, keep a fee, pay them the rest
    when "revenue_share" then "contractor"  # legacy rev-share was generated as incoming (they pay us)
    end
  end

  def has_revenue_projection?
    revenue_projections.present? && revenue_projections["scenarios"].present?
  end

  def revenue_projection_scenario(name = "default")
    return nil unless has_revenue_projection?
    revenue_projections["scenarios"]&.find { |s| s["name"] == name }
  end

  def set_revenue_projection(ticket_price_low:, ticket_price_high:, tickets_sold_low:, tickets_sold_high:, notes: nil, scenario_name: "default")
    scenarios = (revenue_projections["scenarios"] || []).reject { |s| s["name"] == scenario_name }
    scenarios << {
      "name" => scenario_name,
      "ticket_price_low" => ticket_price_low.to_f,
      "ticket_price_high" => ticket_price_high.to_f,
      "tickets_sold_low" => tickets_sold_low.to_i,
      "tickets_sold_high" => tickets_sold_high.to_i,
      "notes" => notes,
      "updated_at" => Time.current.iso8601
    }
    update!(revenue_projections: revenue_projections.merge("scenarios" => scenarios))
  end

  def projected_gross_revenue_range(scenario_name = "default")
    scenario = revenue_projection_scenario(scenario_name)
    return nil unless scenario

    low = scenario["ticket_price_low"].to_f * scenario["tickets_sold_low"].to_i
    high = scenario["ticket_price_high"].to_f * scenario["tickets_sold_high"].to_i
    { low: low, high: high }
  end

  def projected_our_revenue_range(scenario_name = "default")
    gross = projected_gross_revenue_range(scenario_name)
    return nil unless gross && revenue_share_percentage

    share = revenue_share_percentage / 100.0
    { low: (gross[:low] * share).round(2), high: (gross[:high] * share).round(2) }
  end

  def total_received_payments
    contract_payments.where(direction: "incoming", status: "paid").sum(:amount)
  end

  def total_pending_payments
    contract_payments.where(direction: "incoming", status: "pending").sum(:amount)
  end

  # Sync paid course offering payouts to contract payments
  def sync_course_payouts_to_payments
    return if course_offerings.empty?

    # Find all paid line items from course offering payouts
    paid_items = CourseOfferingPayoutLineItem
      .joins(course_offering_payout: :course_offering)
      .where(course_offering_payout: { course_offering_id: course_offerings.ids })
      .where(payee_type: "Contractor", payee_id: contractor_id)
      .where(manually_paid: true)

    paid_items.each do |item|
      # Find matching pending ContractPayment (outgoing, for this contractor)
      payments_to_sync = contract_payments
        .where(direction: "outgoing", status: "pending")
        .select { |p| p.description&.downcase&.include?("revenue share") }

      payments_to_sync.each do |payment|
        payment.mark_paid!(
          paid_on: item.paid_at.to_date,
          method: item.payment_method,
          reference: "Course offering payout",
          amount: item.amount_cents / 100.0
        )
      end
    end
  end

  private

  def deal_money(value)
    format("$%.2f", value.to_f)
  end

  # System-generated "Deal Terms" schedule appended to every signable document —
  # the concrete term, money terms, payment schedule, and services, straight from
  # the contract's own data so the numbers can't drift from a template's wording.
  def deal_terms_html
    esc = ->(s) { ERB::Util.html_escape(s.to_s) }
    out = +%(<hr><h3>Deal Terms</h3>)

    if contract_start_date && contract_end_date
      out << %(<p><strong>Term:</strong> #{esc.(contract_start_date.strftime("%B %-d, %Y"))} – #{esc.(contract_end_date.strftime("%B %-d, %Y"))}</p>)
    end

    summary_lines = (deal_summary rescue [])
    if summary_lines.any?
      out << "<ul>"
      summary_lines.each { |l| out << %(<li><strong>#{esc.(l[:label])}:</strong> #{esc.(l[:value])}</li>) }
      out << "</ul>"
    end

    payments = (draft_payments rescue [])
    if payments.any?
      out << "<h4>Payment schedule</h4><table><thead><tr><th>Item</th><th>Direction</th><th>Amount</th><th>Due</th></tr></thead><tbody>"
      payments.each do |p|
        direction = p["direction"] == "outgoing" ? "We pay them" : "They pay us"
        amount = p["amount_tbd"] ? "TBD" : deal_money(p["amount"])
        due = p["due_date"].present? ? esc.(p["due_date"]) : "—"
        out << %(<tr><td>#{esc.(p["description"].presence || "Payment")}</td><td>#{direction}</td><td>#{amount}</td><td>#{due}</td></tr>)
      end
      out << "</tbody></table>"
    end

    services = (draft_services rescue [])
    if services.any?
      out << "<h4>Services</h4><ul>"
      services.each do |s|
        qty = s["quantity"].to_f
        qty_label = qty > 1 ? " × #{qty.to_i == qty ? qty.to_i : qty}" : ""
        out << %(<li>#{esc.(s["name"])}#{qty_label} — #{deal_money(s["unit_price"])}#{s["unit"] == "hourly" ? "/hr" : ""}</li>)
      end
      out << "</ul>"
    end

    out
  end

  # The inline "License Period and Fees" grid — the dates/stage/rent table a
  # template places itself via {{license_schedule}}. Built entirely from the
  # contract's own bookings + rent so it can't drift, and emitted as a plain
  # <table> the signing view and the PDF walker both already render.
  def license_schedule_html
    esc = ->(s) { ERB::Util.html_escape(s.to_s) }
    rows = license_schedule_rows
    out = +%(<table><thead><tr><th>Dates</th><th>Event</th><th>Start</th><th>End</th><th>Stage</th><th>Rent</th></tr></thead><tbody>)
    if rows.empty?
      out << %(<tr><td colspan="6">Dates to be confirmed.</td></tr>)
    else
      rows.each do |r|
        out << "<tr>"
        out << %(<td>#{esc.(r[:date])}</td><td>#{esc.(r[:event])}</td><td>#{esc.(r[:start])}</td>)
        out << %(<td>#{esc.(r[:end])}</td><td>#{esc.(r[:stage])}</td><td>#{esc.(r[:rent])}</td>)
        out << "</tr>"
      end
    end
    out << "</tbody></table>"
    out << license_payment_schedule_html
    out
  end

  # A second grid, placed just below the dates/rent grid, listing when payments
  # fall due — deposits, installments, "half up front / half on opening". Rendered
  # only when there's a real dated schedule beyond the per-date rent already shown
  # above: pure revenue splits (TBD) don't count, and a per-event rent whose
  # payments all land on the booking dates is already visible in the Rent column,
  # so simple deals get no redundant table.
  def license_payment_schedule_html
    payments = license_concrete_payments
    return "" if payments.empty?

    booking_dates = license_booking_dates
    # Everything already shown as per-date rent above → nothing to add.
    return "" unless payments.any? { |p| booking_dates.exclude?(p[:due]) }

    esc = ->(s) { ERB::Util.html_escape(s.to_s) }
    out = +%(<h4>Payment schedule</h4><table><thead><tr><th>Payment</th><th>Amount</th><th>Due</th></tr></thead><tbody>)
    payments.each do |p|
      out << %(<tr><td>#{esc.(p[:label])}</td><td>#{esc.(p[:amount])}</td><td>#{esc.(p[:due_label])}</td></tr>)
    end
    out << "</tbody></table>"
    out
  end

  # Concrete scheduled payments (real amount, real due date — not TBD revenue-share
  # placeholders), oldest first, shaped for the payment-schedule grid.
  def license_concrete_payments
    draft_payments.filter_map do |p|
      next if p["amount_tbd"]

      amount = p["amount"].to_f
      next unless amount.positive?

      due = parse_booking_time(p["due_date"])&.to_date
      next unless due

      { label: p["description"].presence || "Payment", amount: deal_money(amount),
        due: due, due_label: due.strftime("%b %-d, %Y") }
    end.sort_by { |p| p[:due] }
  end

  # The set of dates the bookings fall on (the rental date) — used to tell whether a
  # payment is "extra" (a deposit/installment worth its own row) or just per-date rent.
  def license_booking_dates
    draft_bookings.filter_map { |b| parse_booking_time(b["starts_at"])&.to_date }
  end

  # The services being rendered on this contract, for the {{services}} token — the
  # deal's own service line items with quantity and rate. Renders its own heading
  # and nothing at all when there are no services, so the token leaves no orphan
  # header behind on a contract without any.
  def license_services_html
    services = (draft_services rescue [])
    return "" if services.blank?

    esc = ->(s) { ERB::Util.html_escape(s.to_s) }
    out = +%(<h4>Services</h4><ul>)
    services.each do |s|
      qty = s["quantity"].to_f
      qty_label = qty > 1 ? " × #{qty.to_i == qty ? qty.to_i : qty}" : ""
      per = s["unit"] == "hourly" ? "/hr" : ""
      out << %(<li>#{esc.(s["name"])}#{qty_label} — #{deal_money(s["unit_price"])}#{per}</li>)
    end
    out << "</ul>"
    out
  end

  # One grid row per booking (date-ordered), drawing only on data the contract
  # already holds. Rent per row is a concrete dated amount when the schedule has
  # one; otherwise it falls back to the deal's pricing expressed in words — a flat
  # fee, a per-event amount, or a revenue share ("50% of ticket sales"). Never
  # "TBD": the Rent cell always states how the money works.
  def license_schedule_rows
    rent_by_date = license_concrete_rent_by_date
    space_names = license_space_names
    rent_label = license_rent_label

    draft_bookings.filter_map do |b|
      # The contract covers the whole booked slot (e.g. 8–11 PM), not the show's own
      # time within it (e.g. 9–10:30) — the rental time is what's being licensed, so
      # the grid shows the booking's start/end, not the event's.
      starts_at = parse_booking_time(b["starts_at"])
      next unless starts_at

      ends_at = booking_end(b, starts_at)
      space_id = (b["location_space_id"].presence || b["space_id"].presence)&.to_i

      {
        date: starts_at.strftime("%a %b %-d, %Y"),
        event: license_event_label(b),
        start: starts_at.strftime("%-l:%M %p"),
        end: ends_at ? ends_at.strftime("%-l:%M %p") : "—",
        stage: space_id ? (space_names[space_id] || "Stage") : "Entire venue",
        rent: rent_by_date[starts_at.to_date] || rent_label
      }
    end
  end

  def parse_booking_time(value)
    return nil if value.blank?

    Time.zone.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def booking_end(booking, starts_at)
    if booking["ends_at"].present?
      parse_booking_time(booking["ends_at"])
    elsif booking["duration"].present?
      starts_at + booking["duration"].to_f.hours
    end
  end

  # A readable event name for the grid: the booking's own event_type when it's a
  # real label, otherwise the production/show name, else a generic fallback.
  def license_event_label(booking)
    raw = booking["event_type"].to_s.strip
    return raw.tr("_", " ").split.map(&:capitalize).join(" ") if raw.present? && raw != "show"

    production_name.presence || production&.name.presence || "Performance"
  end

  # Concrete rent keyed by date, from the payment schedule. Per-event payments
  # carry a due_date on the event date, so this lines each booking up with its own
  # dollar figure. Only real, settled-in amounts land here — TBD/revenue-share
  # placeholders are skipped so they fall through to the worded pricing label.
  def license_concrete_rent_by_date
    draft_payments.each_with_object({}) do |payment, map|
      next if payment["amount_tbd"]

      amount = payment["amount"].to_f
      next unless amount.positive?

      date = parse_booking_time(payment["due_date"])&.to_date
      next unless date

      map[date] ||= deal_money(amount)
    end
  end

  # How the rent reads when there's no concrete dated amount — the deal's pricing
  # stated plainly, per payment structure. Never "TBD".
  def license_rent_label
    cfg = draft_payment_config
    case draft_payment_structure
    when "per_event"
      cfg["per_event_amount"].to_f.positive? ? deal_money(cfg["per_event_amount"]) : "—"
    when "flat_fee"
      license_flat_fee_rent(cfg)
    when "revenue_share"
      license_revenue_share_rent(cfg)
    else
      "—"
    end
  end

  # A flat fee shows the fee itself; the ticket-revenue-minus-fee variant says so.
  def license_flat_fee_rent(cfg)
    return "—" unless cfg["flat_fee_amount"].to_f.positive?

    if cfg["flat_fee_direction"] == "ticket_revenue_minus_fee"
      "Ticket revenue less #{deal_money(cfg['flat_fee_amount'])} fee"
    else
      deal_money(cfg["flat_fee_amount"])
    end
  end

  # A revenue share reads as the venue's cut, e.g. "50% of ticket sales".
  def license_revenue_share_rent(cfg)
    share = (cfg["revenue_our_share"].presence || 50).to_i
    source = {
      "ticket_sales" => "ticket sales", "door_sales" => "door sales",
      "bar_sales" => "bar & concessions", "merchandise" => "merchandise",
      "total_revenue" => "total revenue"
    }[cfg["revenue_source"]] || "ticket sales"
    "#{share}% of #{source}"
  end

  # Names for the stages referenced by the bookings, in one query.
  def license_space_names
    ids = draft_bookings.filter_map { |b| (b["location_space_id"].presence || b["space_id"].presence)&.to_i }.uniq
    return {} if ids.empty?

    LocationSpace.where(id: ids).pluck(:id, :name).to_h
  end

  def deal_summary_flat_fee(cfg, lines)
    if cfg["flat_fee_direction"] == "ticket_revenue_minus_fee"
      lines << { label: "How the money works",
                 value: "They keep the ticket revenue, less our #{deal_money(cfg['flat_fee_amount'])} fee" }
      return
    end

    direction = cfg["flat_fee_direction"] == "outgoing" ? "we pay them" : "they pay us"
    lines << { label: "How the money works", value: "Flat fee of #{deal_money(cfg['flat_fee_amount'])} — #{direction}" }

    return unless cfg["flat_fee_has_deposit"].to_s == "true"

    deposit = if cfg["flat_fee_deposit_amount"].to_f.positive?
      deal_money(cfg["flat_fee_deposit_amount"])
    elsif cfg["flat_fee_deposit_percent"].to_f.positive?
      "#{cfg['flat_fee_deposit_percent']}%"
    end
    lines << { label: "Deposit", value: [ deposit, "upfront" ].compact.join(" ") } if deposit
  end

  def deal_summary_per_event(cfg, lines)
    direction = cfg["per_event_direction"] == "outgoing" ? "we pay them" : "they pay us"
    lines << { label: "How the money works", value: "#{deal_money(cfg['per_event_amount'])} per event — #{direction}" }

    timing = cfg["per_event_timing"] == "upfront" ? "All upfront" : "Event by event"
    lines << { label: "Paid", value: timing }

    if cfg["per_event_has_discount"].to_s == "true" && cfg["per_event_discount_percent"].to_f.positive?
      lines << { label: "Volume discount", value: "#{cfg['per_event_discount_percent']}% off" }
    end
  end

  def deal_summary_revenue_share(cfg, lines)
    our = cfg["revenue_our_share"].presence || 50
    their = cfg["revenue_their_share"].presence || (100 - our.to_i)
    source = {
      "ticket_sales" => "ticket sales", "door_sales" => "door sales",
      "bar_sales" => "bar and concessions", "merchandise" => "merchandise",
      "total_revenue" => "all revenue"
    }[cfg["revenue_source"]] || "ticket sales"
    lines << { label: "How the money works", value: "Revenue share on #{source} — we keep #{our}%, they keep #{their}%" }

    if cfg["revenue_guarantee"].to_s == "true" && cfg["revenue_guarantee_amount"].to_f.positive?
      lines << { label: "Minimum guarantee", value: "They take home at least #{deal_money(cfg['revenue_guarantee_amount'])}" }
    end

    settlement = {
      "same_day" => "Settled same day", "next_day" => "Settled next business day",
      "weekly" => "Settled weekly", "monthly" => "Settled monthly"
    }[cfg["revenue_settlement"]]
    lines << { label: "Settlement", value: settlement } if settlement
  end

  def sync_contractor_info
    return unless contractor_id.present?

    # If contractor is set, ensure contractor_name comes from the contractor
    self.contractor_name = contractor.name if contractor_name.blank? || contractor_id_changed?

    # Optionally sync contact info from contractor if not set on contract
    if contractor_email.blank? && contractor.email.present?
      self.contractor_email = contractor.email
    end
    if contractor_phone.blank? && contractor.phone.present?
      self.contractor_phone = contractor.phone
    end
    if contractor_address.blank? && contractor.address.present?
      self.contractor_address = contractor.address
    end
  end

  def create_records_from_draft!
    rentals = []

    draft_bookings.each do |booking|
      starts_at = Time.zone.parse(booking["starts_at"])

      # Handle both data formats: ends_at directly, or duration-based calculation
      ends_at = if booking["ends_at"].present?
        Time.zone.parse(booking["ends_at"])
      else
        duration_hours = booking["duration"].to_f
        starts_at + duration_hours.hours
      end

      # Get location_id (required) and space_id (optional for "Entire venue")
      location_id = booking["location_id"]
      space_id = booking["location_space_id"] || booking["space_id"]
      space_id = nil if space_id.blank? # Convert empty string to nil

      # Handle event_starts_at if different from rental start
      event_starts_at = booking["event_starts_at"].present? ? Time.zone.parse(booking["event_starts_at"]) : nil
      event_ends_at = booking["event_ends_at"].present? ? Time.zone.parse(booking["event_ends_at"]) : nil

      rental = space_rentals.create!({
        location_id: location_id,
        location_space_id: space_id,
        starts_at: starts_at,
        ends_at: ends_at,
        event_starts_at: event_starts_at,
        event_ends_at: event_ends_at,
        notes: booking["notes"],
        confirmed: true,
        # Honor an override chosen in the wizard. Offline activation sets the
        # transient attr; e-sign persists it in draft_data because the rentals
        # aren't created until the counterparty signs, long after that choice.
        allow_overlap: allow_overlap || draft_data["allow_overlap"] == true
      })

      event_type = booking["event_type"] || "show"
      rentals << { rental: rental, event_type: event_type }
    end

    # Create payments from draft payments
    created_payments = []
    draft_payments.each do |payment|
      created_payments << contract_payments.create!(
        description: payment["description"],
        amount: payment["amount"],
        amount_tbd: payment["amount_tbd"] || false,
        direction: payment["direction"],
        due_date: payment["due_date"],
        notes: payment["notes"]
      )
    end

    # Services become their own billable payments (this is what "Tech" never did).
    bill_services!(draft_services)

    # Always create a production and shows for all bookings
    created_shows = []
    if rentals.any?
      prod_data = draft_data["production"] || {}
      # Reuse an existing production rather than creating a duplicate:
      #   1. one already attached to this contract, or
      #   2. one the user explicitly chose to link when starting the contract.
      # Only create a fresh third_party production when neither exists.
      linked_production_id = draft_data["link_production_id"].presence
      production = self.production
      production ||= organization.productions.find_by(id: linked_production_id) if linked_production_id
      production ||= organization.productions.create!(
        name: production_name.presence || prod_data["name"].presence || contractor_name,
        production_type: "third_party",
        contact_email: contractor_email
      )

      # Attach this contract to that production (a production can carry many contracts).
      update!(production: production) unless self.production_id == production.id

      rentals.each do |info|
        rental = info[:rental]
        # The show represents the event, so it runs at the event time when one
        # was set within the booked slot — not the whole slot.
        show = production.shows.create!(
          date_and_time: rental.effective_event_starts_at,
          duration_minutes: rental.effective_duration_minutes,
          location: rental.location,
          location_space: rental.location_space,
          space_rental: rental,
          event_type: info[:event_type]
        )
        created_shows << show
      end
    end

    # Link per-event payments to their corresponding shows
    link_payments_to_shows(created_payments, created_shows)
  end

  # Link per-event contract payments to their corresponding shows by matching dates
  def link_payments_to_shows(payments, shows)
    return if payments.empty? || shows.empty?

    settlement = draft_payment_config["revenue_settlement"] || "monthly"
    structure = draft_payment_structure

    # Only link for per-event or per-event revenue share settlements
    per_event_structures = %w[per_event]
    per_event_settlements = %w[per_event same_day next_day]

    should_link = per_event_structures.include?(structure) ||
                  (structure == "revenue_share" && per_event_settlements.include?(settlement))
    return unless should_link

    # Sort both by date and pair 1:1
    sorted_shows = shows.sort_by(&:date_and_time)
    # Per-event payments are named for their event date now (e.g. "Jul 1 event"),
    # so match the word case-insensitively; revenue-share ones are amount_tbd.
    sorted_payments = payments.select { |p| p.amount_tbd? || p.description&.downcase&.include?("event") || p.description&.downcase&.include?("revenue share") }
                              .sort_by(&:due_date)

    sorted_payments.each_with_index do |payment, i|
      next unless sorted_shows[i]
      payment.update_column(:show_id, sorted_shows[i].id)
    end
  end
end
