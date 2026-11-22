# frozen_string_literal: true

# What a production has for each item on its organization's list (AssetSpec),
# and the one way anything is added to it: by a manager on the Visual Assets
# tab, by someone with the request's link, or by someone on the contract
# from My Contracts.
#
# The built-ins write through to where the app already reads them, so no
# page that shows a production's pictures changes: the Poster becomes the
# production's primary poster (the one before it stays as another poster),
# the Wide image is its wide_image, and the Show description is its
# description. A ProductionAsset row remembers who added each and when.
class ProductionAssets
  class Item
    attr_reader :spec, :record

    def initialize(production, spec, record)
      @production = production
      @spec = spec
      @record = record
    end

    def present?
      return text.present? if spec.text?

      attachment.present?
    end

    # The original file, for Download original.
    def attachment
      return nil if spec.text?

      case spec.builtin
      when "poster" then @production.primary_poster&.image&.then { |image| image.attached? ? image : nil }
      when "wide" then @production.wide_image.attached? ? @production.wide_image : nil
      else record&.file&.attached? ? record.file : nil
      end
    end

    def preview
      case spec.builtin
      when "poster" then @production.primary_poster&.safe_image_variant(:small)
      when "wide" then @production.safe_wide_image_variant(:small)
      else record&.preview
      end
    end

    def width = record&.width || attachment&.blob&.metadata&.dig("width")
    def height = record&.height || attachment&.blob&.metadata&.dig("height")

    def text
      return nil unless spec.text?
      return @production.description&.to_plain_text.to_s.strip.presence if spec.builtin == "description"

      record&.text_value.to_s.strip.presence
    end

    def file_words
      return nil unless (file = attachment)

      parts = []
      parts << "#{width} × #{height}" if width && height
      ext = File.extname(file.filename.to_s).delete(".").upcase.presence
      parts << ext if ext
      parts.join(", ")
    end

    # "Added by Dana Whitfield today at 2:16 PM". A picture added before
    # this list existed says only when.
    def uploaded_words
      return record.uploaded_words if record&.changed_at

      added = attachment&.blob&.created_at
      added ? "Added on #{added.strftime('%B %-d')}" : nil
    end
  end

  Counts = Data.define(:done, :total, :missing_required, :missing_optional) do
    def complete? = missing_required.empty?

    # Every item on the list is in, optional ones too.
    def all_in? = total.positive? && done == total
  end

  attr_reader :production

  def initialize(production)
    @production = production
  end

  def specs
    @specs ||= AssetSpec.for(production.organization).to_a
  end

  def image_specs = specs.select(&:image?)
  def text_specs = specs.select(&:text?)

  def records
    @records ||= production.production_assets.where.not(asset_spec_id: nil).includes(:uploaded_by_user, file_attachment: :blob).index_by(&:asset_spec_id)
  end

  # In the order the pages show them: the images, then the written items.
  def items
    @items ||= (image_specs + text_specs).map { |spec| item(spec) }
  end

  def item(spec)
    Item.new(production, spec, records[spec.id])
  end

  # Every image item that has a file, with its original, for Download all
  # originals: [[spec, attachment], ...] in the tab's order.
  def originals
    image_specs.filter_map { |spec| (file = item(spec).attachment) && [ spec, file ] }
  end

  # One zip of those originals, each named for its item ("Poster.jpg",
  # "Wide image.png"), a second of the same name numbered.
  def originals_zip
    names = Hash.new(0)
    buffer = Zip::OutputStream.write_buffer do |zip|
      originals.each do |spec, file|
        stem = spec.name.to_s.gsub(%r{[/\\:*?"<>|]}, "-").strip.presence || "Image"
        names[stem] += 1
        zip.put_next_entry("#{stem}#{" (#{names[stem]})" if names[stem] > 1}#{file.filename.extension_with_delimiter}")
        zip.write file.download
      end
    end
    buffer.string
  end

  def additional_files
    production.production_assets.additional.includes(:uploaded_by_user, file_attachment: :blob).order(:created_at)
  end

  def counts
    done = items.select(&:present?)
    missing = items.reject(&:present?)
    Counts.new(done: done.size, total: items.size,
               missing_required: missing.select { |item| item.spec.required? }.map { |item| item.spec.name },
               missing_optional: missing.reject { |item| item.spec.required? }.map { |item| item.spec.name })
  end

  # Keeps a file that AssetCheck passed. Returns the ProductionAsset.
  def store_file!(spec, file, check:, user: nil, name: nil, request: nil)
    was_present = item(spec).present?
    record = production.production_assets.find_or_initialize_by(asset_spec_id: spec.id)

    ProductionAsset.transaction do
      case spec.builtin
      when "poster" then production.posters.create!(image: file, is_primary: true)
      when "wide" then production.update!(wide_image: file)
      else record.file.attach(file)
      end
      record.assign_attributes(width: check.width, height: check.height, uploaded_by_user: user, uploaded_by_name: name.presence,
                               asset_request: request, last_change: was_present ? "replaced" : "added", changed_at: Time.current)
      record.save!
    end
    reset!
    record
  end

  # Keeps a written item. Returns true when the words changed.
  def store_text!(spec, words, user: nil, name: nil, request: nil)
    words = words.to_s.strip
    words = words.first(spec.max_length) if spec.max_length
    before = item(spec).text.to_s
    return false if before == words

    record = production.production_assets.find_or_initialize_by(asset_spec_id: spec.id)
    ProductionAsset.transaction do
      if spec.builtin == "description"
        production.update!(description: words.present? ? paragraphs(words) : nil)
      else
        record.text_value = words.presence
      end
      record.assign_attributes(uploaded_by_user: user, uploaded_by_name: name.presence, asset_request: request,
                               last_change: before.present? ? "replaced" : "added", changed_at: Time.current)
      record.save!
    end
    reset!
    true
  end

  # Takes a custom item's file or words away (a manager's Remove).
  def remove!(spec)
    record = records[spec.id]
    return unless record

    record.file.purge_later if record.file.attached?
    record.destroy!
    reset!
  end

  private

  def paragraphs(words)
    words.split(/\n{2,}/).map { |para| "<p>#{ERB::Util.html_escape(para).gsub("\n", '<br>')}</p>" }.join
  end

  def reset!
    @records = nil
    @items = nil
    production.reload
  end
end
