require 'rails_helper'

RSpec.describe CallToAudition, type: :model do
  describe "validations" do
    it "is valid with valid attributes" do
      call = build(:call_to_audition)
      expect(call).to be_valid
    end

    it "is invalid without opens_at" do
      call = build(:call_to_audition, opens_at: nil)
      expect(call).not_to be_valid
      expect(call.errors[:opens_at]).to include("can't be blank")
    end

    it "is invalid without closes_at" do
      call = build(:call_to_audition, closes_at: nil)
      expect(call).not_to be_valid
      expect(call.errors[:closes_at]).to include("can't be blank")
    end
  end

  describe "associations" do
    it "belongs to production" do
      call = create(:call_to_audition)
      expect(call.production).to be_present
      expect(call).to respond_to(:production)
    end

    it "has many audition_requests" do
      call = create(:call_to_audition)
      expect(call).to respond_to(:audition_requests)
    end

    it "has many audition_sessions" do
      call = create(:call_to_audition)
      expect(call).to respond_to(:audition_sessions)
    end

    it "has many questions" do
      call = create(:call_to_audition)
      expect(call).to respond_to(:questions)
    end
  end

  describe "audition_type enum" do
    it "can be in_person" do
      call = create(:call_to_audition, audition_type: :in_person)
      expect(call.audition_type).to eq("in_person")
      expect(call.in_person?).to be true
    end

    it "can be video_upload" do
      call = create(:call_to_audition, :video_upload)
      expect(call.audition_type).to eq("video_upload")
      expect(call.video_upload?).to be true
    end
  end

  describe "#production_name" do
    it "returns the name of the associated production" do
      production = create(:production, name: "The Lion King")
      call = create(:call_to_audition, production: production)

      expect(call.production_name).to eq("The Lion King")
    end
  end

  describe "#counts" do
    let(:call) { create(:call_to_audition) }

    it "returns counts for each status" do
      create(:audition_request, call_to_audition: call, status: :unreviewed)
      create(:audition_request, call_to_audition: call, status: :unreviewed)
      create(:audition_request, call_to_audition: call, status: :undecided)
      create(:audition_request, call_to_audition: call, status: :passed)
      create(:audition_request, call_to_audition: call, status: :accepted)

      counts = call.counts
      expect(counts[:unreviewed]).to eq(2)
      expect(counts[:undecided]).to eq(1)
      expect(counts[:passed]).to eq(1)
      expect(counts[:accepted]).to eq(1)
    end

    it "returns zero for statuses with no requests" do
      counts = call.counts
      expect(counts[:unreviewed]).to eq(0)
      expect(counts[:undecided]).to eq(0)
      expect(counts[:passed]).to eq(0)
      expect(counts[:accepted]).to eq(0)
    end
  end

  describe "#timeline_status" do
    it "returns :upcoming when opens_at is in the future" do
      call = create(:call_to_audition, :upcoming)
      expect(call.timeline_status).to eq(:upcoming)
    end

    it "returns :open when current time is between opens_at and closes_at" do
      call = create(:call_to_audition, opens_at: 1.day.ago, closes_at: 1.day.from_now)
      expect(call.timeline_status).to eq(:open)
    end

    it "returns :closed when closes_at is in the past" do
      call = create(:call_to_audition, :closed)
      expect(call.timeline_status).to eq(:closed)
    end
  end

  describe "#respond_url" do
    let(:call) { create(:call_to_audition, token: "abc123xyz") }

    it "returns development URL in development environment" do
      allow(Rails.env).to receive(:development?).and_return(true)
      expect(call.respond_url).to eq("http://localhost:3000/a/abc123xyz")
    end

    it "returns production URL in non-development environment" do
      allow(Rails.env).to receive(:development?).and_return(false)
      expect(call.respond_url).to eq("https://www.cocoscout.com/a/abc123xyz")
    end
  end

  describe "rich text fields" do
    it "has header_text as rich text" do
      call = create(:call_to_audition)
      call.update(header_text: "<p>Welcome to auditions!</p>")

      expect(call.header_text.to_s).to include("Welcome to auditions!")
    end

    it "has video_field_text as rich text" do
      call = create(:call_to_audition)
      call.update(video_field_text: "<p>Upload your video here</p>")

      expect(call.video_field_text.to_s).to include("Upload your video here")
    end

    it "has success_text as rich text" do
      call = create(:call_to_audition)
      call.update(success_text: "<p>Thank you for applying!</p>")

      expect(call.success_text.to_s).to include("Thank you for applying!")
    end
  end
end
