# frozen_string_literal: true

# The one way a production's images and words arrive (Tim, 2026-11-19),
# shared by the three places they can be added: the production's Visual
# Assets tab (a manager), the request's no-login page (anyone with the link),
# and My Contracts (someone on the contract, signed in). Each file is held
# to its specification by AssetCheck before anything is kept.
#
# The including controller says whose production it is and who is adding:
#   asset_production        the Production
#   asset_uploader_user     the signed-in User, or nil
#   asset_uploader_name     the name to show beside what they added
#   asset_request_for_log   the AssetRequest it arrived through, or nil
#   asset_may_replace?(item) whether something already there may be replaced
#   asset_after_change      what happens next (the request notes activity)
#   asset_page_locals       locals for the card and progress partials
module AssetUploading
  extend ActiveSupport::Concern

  private

  def asset_assets
    @asset_assets ||= ProductionAssets.new(asset_production)
  end

  def asset_spec_from_params(kind)
    asset_assets.specs.find { |spec| spec.id == params[:spec_id].to_i && spec.kind == kind }
  end

  # POST: one file for one image. Answers JSON: ok, or the sentence saying
  # why not; with the card and the progress line redrawn when it worked.
  def perform_asset_upload(cards: true)
    spec = asset_spec_from_params("image")
    return render(json: { ok: false, message: "That item is no longer on the list. Reload the page to see what is." }, status: :not_found) unless spec

    item = asset_assets.item(spec)
    if item.present? && !asset_may_replace?(item)
      return render(json: { ok: false, message: "#{spec.name} has already been added. Request a change from #{asset_production.organization.name} if you need one." },
                    status: :unprocessable_content)
    end

    check = AssetCheck.call(spec, params[:file])
    return render(json: { ok: false, message: check.message }, status: :unprocessable_content) unless check.ok?

    asset_assets.store_file!(spec, params[:file], check: check, user: asset_uploader_user, name: asset_uploader_name, request: asset_request_for_log)
    asset_after_change
    render json: asset_success_json(spec, cards)
  rescue ActiveRecord::RecordInvalid => e
    render json: { ok: false, message: e.record.errors.full_messages.to_sentence }, status: :unprocessable_content
  end

  # PATCH: a written item, saved as it's typed.
  def perform_asset_text_save(cards: true)
    spec = asset_spec_from_params("text")
    return render(json: { ok: false, message: "That item is no longer on the list. Reload the page to see what is." }, status: :not_found) unless spec

    words = params[:text].to_s
    item = asset_assets.item(spec)
    if item.present? && words.strip != item.text.to_s && !asset_may_replace?(item)
      return render(json: { ok: false, message: "#{spec.name} has already been added. Request a change from #{asset_production.organization.name} if you need one." },
                    status: :unprocessable_content)
    end

    changed = asset_assets.store_text!(spec, words, user: asset_uploader_user, name: asset_uploader_name, request: asset_request_for_log)
    asset_after_change if changed
    render json: asset_success_json(spec, cards).merge(saved: true)
  rescue ActiveRecord::RecordInvalid => e
    render json: { ok: false, message: e.record.errors.full_messages.to_sentence }, status: :unprocessable_content
  end

  def asset_success_json(spec, cards)
    return { ok: true } unless cards

    item = asset_assets.item(spec)
    locals = asset_page_locals
    partial = spec.image? ? "asset_requests/card" : "asset_requests/text_status"
    {
      ok: true,
      card_html: render_to_string(partial: partial, formats: [ :html ], locals: locals.merge(item: item)),
      progress_html: render_to_string(partial: "asset_requests/progress", formats: [ :html ], locals: locals.merge(counts: asset_assets.counts))
    }
  end

  # With "Let them replace what is already here" off, what was there before
  # the request stays put; what they added through it, they can change.
  def asset_added_through?(item, request)
    request && item.record&.asset_request_id == request.id
  end

  # Who to show beside what someone added through the link: their account's
  # name, else the name they typed on the page (kept for their visit).
  def asset_typed_name
    typed = params[:uploader_name].to_s.squish.first(80)
    session[:asset_uploader_name] = typed if typed.present?
    typed.presence || session[:asset_uploader_name].presence
  end
end
