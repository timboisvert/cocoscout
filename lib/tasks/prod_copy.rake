# frozen_string_literal: true

# A scrubbed copy of production for dev (Tim, 2026-11-01). bin/prod_copy runs
# these in order; see the top of that script for the whole flow.
namespace :prod_copy do
  desc "Scrub a restored production copy (DEV_DATABASE must name it, and contain 'prodcopy'). KEEP_EMAIL keeps one login."
  task scrub: :environment do
    copied_on = ENV["COPY_DATE"].present? ? Date.parse(ENV["COPY_DATE"]) : Date.current
    report = Dev::ProdCopyScrubber.new(keep_email: ENV.fetch("KEEP_EMAIL", "boisvert@gmail.com"), copied_on: copied_on).run!
    report.sort.each { |what, count| puts format("  %-60s %d", what, count) }
    puts "Scrubbed #{ActiveRecord::Base.connection.current_database}. Your login (#{ENV.fetch('KEEP_EMAIL', 'boisvert@gmail.com')}) is the only one that works."
  end

  desc "List the stored files a production copy refers to, for copying into the development bucket (W-9s left out)."
  task files: :environment do
    unless Rails.env.development? && ActiveRecord::Base.connection.current_database.include?("prodcopy")
      abort "Run against the copy: DEV_DATABASE=cocoscout_prodcopy bin/rails prod_copy:files"
    end

    # Tax forms stay in production: a W-9 carries a full taxpayer number.
    sensitive = %w[W9Submission]
    blob_ids = ActiveStorage::Attachment.where.not(record_type: sensitive).distinct.pluck(:blob_id)
    keys = ActiveStorage::Blob.where(id: blob_ids).pluck(:key)
    path = Rails.root.join("tmp/prod_copy/blob_keys.txt")
    FileUtils.mkdir_p(path.dirname)
    File.write(path, keys.join("\n") + "\n")
    puts "#{keys.size} files listed in #{path.relative_path_from(Rails.root)}. Copy them with your own AWS credentials:"
    puts "  xargs -P 8 -I{} aws s3 cp s3://cocoscout-production/{} s3://cocoscout-development/{} --only-show-errors < #{path.relative_path_from(Rails.root)}"
  end
end
