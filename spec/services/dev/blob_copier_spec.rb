# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dev::BlobCopier do
  let(:out) { StringIO.new }

  def client_with(existing: [], copy: nil)
    client = Aws::S3::Client.new(stub_responses: true, region: "us-east-2")
    client.stub_responses(:list_objects_v2, { contents: existing.map { |key| { key: key } } })
    client.stub_responses(:copy_object, copy) if copy
    client
  end

  it "copies what dev doesn't have yet, inside S3" do
    client = client_with(existing: %w[a])
    result = described_class.new(client: client, from: "cocoscout-production", to: "cocoscout-development", keys: %w[a b c c], out: out).run!

    expect(result).to have_attributes(listed: 3, already_there: 1, copied: 2, missing: 0)
    copies = client.api_requests.select { |r| r[:operation_name] == :copy_object }.map { |r| r[:params] }
    expect(copies).to contain_exactly(
      { bucket: "cocoscout-development", key: "b", copy_source: "cocoscout-production/b" },
      { bucket: "cocoscout-development", key: "c", copy_source: "cocoscout-production/c" }
    )
  end

  it "counts files production no longer has, and stops on a permissions problem" do
    gone = described_class.new(client: client_with(copy: "NoSuchKey"), from: "p", to: "d", keys: %w[x y], out: out).run!
    expect(gone).to have_attributes(copied: 0, missing: 2)

    denied = described_class.new(client: client_with(copy: "AccessDenied"), from: "p", to: "d", keys: %w[x y], out: out)
    expect { denied.run! }.to raise_error(described_class::AccessDenied, /read on p/)
  end

  it "never copies into production" do
    expect { described_class.new(client: client_with, from: "a", to: "cocoscout-production", keys: [], out: out) }.to raise_error(ArgumentError)
  end

  it "lists attached images only, not documents, W-9s or their variants" do
    org = create(:organization)
    kept = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("logo"), filename: "logo.png", content_type: "image/png")
    org.logo.attach(kept)
    resume = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("cv"), filename: "cv.pdf", content_type: "application/pdf")
    ActiveStorage::Attachment.insert_all!([ { name: "file", record_type: "ProfileResume", record_id: 1, blob_id: resume.id, created_at: Time.current } ])
    left_out = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("tax"), filename: "w9.pdf")
    ActiveStorage::Attachment.insert_all!([ { name: "pdf", record_type: "W9Submission", record_id: 1, blob_id: left_out.id, created_at: Time.current } ])
    variant = ActiveStorage::VariantRecord.create!(blob: left_out, variation_digest: "x")
    variant_blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("v"), filename: "v.png", content_type: "image/png")
    ActiveStorage::Attachment.insert_all!([ { name: "image", record_type: "ActiveStorage::VariantRecord", record_id: variant.id, blob_id: variant_blob.id, created_at: Time.current } ])

    expect(described_class.keys).to contain_exactly(kept.key)
  end
end
