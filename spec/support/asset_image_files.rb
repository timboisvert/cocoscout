# frozen_string_literal: true

# Real image files of a given size, for visual asset specs (AssetCheck reads
# the pixels, so a fixture of the wrong size won't do).
module AssetImageFiles
  def asset_image(width, height, name: "picture.png")
    dir = Rails.root.join("tmp", "spec-asset-images")
    FileUtils.mkdir_p(dir)
    path = dir.join("#{SecureRandom.hex(4)}-#{name}")
    Vips::Image.black(width, height).write_to_file(path.to_s)
    Rack::Test::UploadedFile.new(path.to_s, Marcel::MimeType.for(name: name), original_filename: name)
  end
end

RSpec.configure do |config|
  config.include AssetImageFiles
end
