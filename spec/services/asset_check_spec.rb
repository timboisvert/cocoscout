# frozen_string_literal: true

require "rails_helper"

# A file that doesn't meet its specification is refused, and says why (Tim,
# 2026-11-19). The checker reads the file itself, never what it's called.
RSpec.describe AssetCheck do
  let(:square) { AssetSpec.new(name: "Instagram square", kind: "image", width: 1080, height: 1080, formats: %w[jpg png], max_megabytes: 10) }

  it "takes a file of the right shape, at the size or bigger" do
    expect(described_class.call(square, asset_image(1080, 1080))).to be_ok
    result = described_class.call(square, asset_image(2000, 2000))
    expect(result).to be_ok
    expect([ result.width, result.height ]).to eq([ 2000, 2000 ])
  end

  it "refuses the wrong shape, naming both shapes" do
    result = described_class.call(square, asset_image(1080, 1350, name: "ig.png"))
    expect(result).not_to be_ok
    expect(result.message).to eq(%(We couldn't use "ig.png". It is 1080 × 1350, which is taller than it is wide. This one needs to be square, 1080 × 1080 or larger.))
  end

  it "refuses the right shape when it is too small" do
    result = described_class.call(square, asset_image(540, 540, name: "small.png"))
    expect(result.message).to eq(%(We couldn't use "small.png". It is 540 × 540, which is the right shape but too small. This one needs to be at least 1080 × 1080.))
  end

  it "names a wide shape by its ratio" do
    wide = AssetSpec.new(name: "Lobby TV", kind: "image", width: 1920, height: 1080, formats: %w[jpg png], max_megabytes: 10)
    result = described_class.call(wide, asset_image(1080, 1080, name: "sq.png"))
    expect(result.message).to include("which is square. This one needs to be wide (16:9), 1920 × 1080 or larger.")
  end

  it "allows a shape off by under 1%" do
    wide = AssetSpec.new(name: "Lobby TV", kind: "image", width: 1920, height: 1080, formats: %w[png], max_megabytes: 10)
    expect(described_class.call(wide, asset_image(1920, 1085))).to be_ok
  end

  it "won't take a file that only claims to be a picture" do
    path = Rails.root.join("tmp", "spec-asset-images", "#{SecureRandom.hex(4)}.png")
    FileUtils.mkdir_p(path.dirname)
    File.write(path, "just some words")
    result = described_class.call(square, Rack::Test::UploadedFile.new(path.to_s, "image/png", original_filename: "fake.png"))
    expect(result).not_to be_ok
    expect(result.message).to eq(%(We couldn't read "fake.png" as an image. Try saving it again as JPG or PNG.))
  end

  it "names the kind of file it really is" do
    path = Rails.root.join("tmp", "spec-asset-images", "#{SecureRandom.hex(4)}.pdf")
    FileUtils.mkdir_p(path.dirname)
    Prawn::Document.new.render_file(path.to_s)
    result = described_class.call(square, Rack::Test::UploadedFile.new(path.to_s, "image/png", original_filename: "poster.png"))
    expect(result.message).to eq(%(We couldn't use "poster.png". It is a PDF, and this one needs to be JPG or PNG.))
  end

  it "refuses a file over the size limit" do
    tiny_limit = AssetSpec.new(name: "Square", kind: "image", width: 10, height: 10, formats: %w[png], max_megabytes: 1)
    allow(File).to receive(:size).and_call_original
    file = asset_image(20, 20, name: "big.png")
    allow(File).to receive(:size).with(file.path).and_return(3.megabytes)
    expect(described_class.call(tiny_limit, file).message).to eq(%(We couldn't use "big.png". It is 3 MB, and this one can be up to 1 MB.))
  end

  it "reads a PDF's first page in inches at the specification's DPI" do
    print = AssetSpec.new(name: "Print poster", kind: "image", width: 3300, height: 5100, dpi: 300, formats: %w[pdf], max_megabytes: 50)
    pdf = Prawn::Document.new(page_size: [ 792, 1224 ], margin: 0)
    path = Rails.root.join("tmp", "spec-asset-images", "#{SecureRandom.hex(4)}.pdf")
    FileUtils.mkdir_p(path.dirname)
    pdf.render_file(path.to_s)
    result = described_class.call(print, Rack::Test::UploadedFile.new(path.to_s, "application/pdf", original_filename: "poster.pdf"))
    expect(result).to be_ok
    expect([ result.width, result.height ]).to eq([ 3300, 5100 ])
  end
end
