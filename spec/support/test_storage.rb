# frozen_string_literal: true

# Every upload a spec makes lands in this process's own test storage folder
# (config/storage.yml), which is emptied when the run ends. Left alone, they
# grew to 18 GB in tmp/storage (Tim, 2026-11-20).
RSpec.configure do |config|
  config.after(:suite) do
    root = ActiveStorage::Blob.service.try(:root)
    FileUtils.rm_rf(Dir.glob(File.join(root, "*"))) if root.to_s.include?("/tmp/storage")
  end
end
