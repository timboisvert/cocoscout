# frozen_string_literal: true

require "open3"

# Holds an uploaded file to an AssetSpec before anything is kept (Tim,
# 2026-11-19: a file that doesn't meet the specification is refused, and
# says why). It reads the file itself, never what the browser claims: the
# type from its bytes, the size in pixels from the image (turned upright, as
# phone photos are stored sideways), and a PDF's first page in inches at the
# specification's DPI (300 when it has none).
#
#   result = AssetCheck.call(spec, uploaded_file)
#   result.ok?      # => false
#   result.message  # => "We couldn't use \"ig.png\". It is 1080 × 1350, ..."
#
# A bigger file of the right shape is fine. The shape may be off by 1%.
class AssetCheck
  Result = Data.define(:ok, :message, :width, :height, :content_type) do
    def ok? = ok
  end

  TOLERANCE = 0.01
  PDF_DPI = 300

  def self.call(spec, file) = new(spec, file).call

  def initialize(spec, file)
    @spec = spec
    @file = file
  end

  def call
    return refuse("Choose a file to upload.") if @file.blank? || !@file.respond_to?(:path)

    name = @file.respond_to?(:original_filename) ? @file.original_filename.to_s : File.basename(@file.path)
    @label = %("#{name.truncate(60)}")
    @content_type = Marcel::MimeType.for(Pathname.new(@file.path), name: name)

    return refuse("We couldn't use #{@label}. It is #{type_words(@content_type)}, and this one needs to be #{@spec.formats_words}.") unless @spec.content_types.include?(@content_type)

    size = File.size(@file.path)
    if size > @spec.max_bytes
      return refuse("We couldn't use #{@label}. It is #{megabytes(size)}, and this one can be up to #{@spec.max_megabytes} MB.")
    end

    width, height = dimensions
    return refuse("We couldn't read #{@label} as #{@content_type == 'application/pdf' ? 'a PDF' : 'an image'}. Try saving it again as #{@spec.formats_words}.") unless width && height

    unless same_shape?(width, height)
      return refuse("We couldn't use #{@label}. It is #{width} × #{height}, which is #{file_shape(width, height)}. " \
                    "This one needs to be #{wanted_shape}, #{@spec.width} × #{@spec.height} or larger.", width, height)
    end

    if width < @spec.width || height < @spec.height
      return refuse("We couldn't use #{@label}. It is #{width} × #{height}, which is the right shape but too small. " \
                    "This one needs to be at least #{@spec.width} × #{@spec.height}.", width, height)
    end

    Result.new(ok: true, message: nil, width: width, height: height, content_type: @content_type)
  end

  private

  def refuse(message, width = nil, height = nil)
    Result.new(ok: false, message: message, width: width, height: height, content_type: @content_type)
  end

  def dimensions
    @content_type == "application/pdf" ? pdf_dimensions : image_dimensions
  end

  def image_dimensions
    image = Vips::Image.new_from_file(@file.path, access: :sequential)
    width = image.width
    height = image.height
    orientation = image.get_typeof("orientation").zero? ? 1 : image.get("orientation").to_i
    orientation.between?(5, 8) ? [ height, width ] : [ width, height ]
  rescue Vips::Error, StandardError
    nil
  end

  # "Page size: 792 x 1224 pts" → pixels at the specification's DPI.
  def pdf_dimensions
    out, status = Open3.capture2("pdfinfo", "-f", "1", "-l", "1", @file.path)
    return nil unless status.success?

    match = out.match(/Page\s+1\s+size:\s+([\d.]+)\s+x\s+([\d.]+)\s+pts/) || out.match(/Page size:\s+([\d.]+)\s+x\s+([\d.]+)\s+pts/)
    return nil unless match

    rotation = out[/Page\s+1\s+rot:\s+(\d+)/, 1].to_i
    dpi = @spec.dpi || PDF_DPI
    width = (match[1].to_f / 72 * dpi).round
    height = (match[2].to_f / 72 * dpi).round
    rotation.in?([ 90, 270 ]) ? [ height, width ] : [ width, height ]
  rescue StandardError
    nil
  end

  def same_shape?(width, height)
    want = @spec.width.to_f / @spec.height
    have = width.to_f / height
    (have - want).abs / want <= TOLERANCE
  end

  def file_shape(width, height)
    ratio = width.to_f / height
    return "square" if (ratio - 1).abs <= TOLERANCE

    ratio > 1 ? "wider than it is tall" : "taller than it is wide"
  end

  def wanted_shape
    return "square" if @spec.square?

    "#{@spec.width > @spec.height ? 'wide' : 'tall'} (#{@spec.ratio_label})"
  end

  def type_words(content_type)
    {
      "image/jpeg" => "a JPG", "image/png" => "a PNG", "image/webp" => "a WebP image", "application/pdf" => "a PDF",
      "image/gif" => "a GIF", "image/heic" => "a HEIC photo", "image/heif" => "a HEIC photo", "image/tiff" => "a TIFF",
      "image/svg+xml" => "an SVG"
    }.fetch(content_type) { content_type.to_s.start_with?("text/") ? "a text file" : "a different kind of file" }
  end

  def megabytes(bytes)
    "#{(bytes.to_f / 1.megabyte).round(1).to_s.sub(/\.0\z/, '')} MB"
  end
end
