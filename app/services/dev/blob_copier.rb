# frozen_string_literal: true

require "aws-sdk-s3"

# Copies production's images (headshots, posters, show and production images,
# logos, message images, and their resized versions) into the dev bucket after the dev
# database is seeded from production (bin/seed_dev_from_prod). The copy
# happens inside S3, many at once, and skips files dev already has, so a
# second run picks up where the first stopped.
#
# Images only: documents (résumés, contracts, statements, W-9s), their
# previews, and email logs stay in production. Dev doesn't need them, and W-9s
# and email logs carry what the scrub took out of the database. About 1.6 GB
# (Nov 2026), a few cents a month in S3.
module Dev
  class BlobCopier
    LEFT_OUT = %w[W9Submission EmailLog].freeze
    THREADS = 16

    class AccessDenied < StandardError; end

    Result = Data.define(:listed, :already_there, :copied, :missing)

    def self.keys
      left_out_blobs = ActiveStorage::Attachment.where(record_type: LEFT_OUT).select(:blob_id)
      left_out_variants = ActiveStorage::VariantRecord.where(blob_id: left_out_blobs).select(:id)
      blob_ids = ActiveStorage::Attachment.where.not(record_type: LEFT_OUT + [ "ActiveStorage::Blob" ])
                                          .where.not(record_type: "ActiveStorage::VariantRecord", record_id: left_out_variants)
                                          .distinct.pluck(:blob_id)
      ActiveStorage::Blob.where(id: blob_ids).where("content_type LIKE 'image/%'").pluck(:key)
    end

    def initialize(client:, from:, to:, keys:, out: $stdout)
      raise ArgumentError, "Copying from #{from} into itself" if from == to
      raise ArgumentError, "Refusing to copy into #{to}" if to.include?("production")

      @client = client
      @from = from
      @to = to
      @keys = keys.uniq
      @out = out
    end

    def run!
      there = existing_keys
      todo = @keys.reject { |key| there.include?(key) }
      @out.puts "#{@keys.size} files; #{@keys.size - todo.size} already in #{@to}, #{todo.size} to copy."
      copied = 0
      missing = 0
      return Result.new(@keys.size, @keys.size - todo.size, 0, 0) if todo.empty?

      # The first one alone, so a permissions problem stops it straight away.
      first = todo.shift
      copy(first) ? copied += 1 : missing += 1

      queue = Queue.new
      todo.each { |key| queue << key }
      lock = Mutex.new
      failure = nil
      Array.new([ THREADS, todo.size ].min) do
        Thread.new do
          while failure.nil? && (key = (queue.pop(true) rescue nil))
            begin
              found = copy(key)
            rescue AccessDenied => e
              lock.synchronize { failure ||= e }
              break
            end
            lock.synchronize do
              found ? copied += 1 : missing += 1
              done = copied + missing
              @out.puts "  #{done} of #{todo.size + 1} copied" if (done % 500).zero?
            end
          end
        end
      end.each(&:join)
      raise failure if failure

      @out.puts "Copied #{copied}.#{" #{missing} weren't in #{@from} any more." if missing.positive?}"
      Result.new(@keys.size, @keys.size - todo.size - 1, copied, missing)
    end

    private

    def copy(key)
      @client.copy_object(bucket: @to, key: key, copy_source: "#{@from}/#{ERB::Util.url_encode(key)}")
      true
    rescue Aws::S3::Errors::NoSuchKey
      false
    rescue Aws::S3::Errors::AccessDenied => e
      raise AccessDenied, "Not allowed to copy from #{@from} into #{@to} (#{e.message}). The AWS user in .env needs read on #{@from}."
    end

    def existing_keys
      keys = Set.new
      @client.list_objects_v2(bucket: @to).each { |page| page.contents.each { |object| keys << object.key } }
      keys
    end
  end
end
